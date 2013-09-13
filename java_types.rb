#!/usr/bin/ruby -w

require "set"

#{{{ Extensions

##
# Some utility methods for strings.
class String
    ##
    # Remove _n_ leading spaces from the string in-place, and then return
    # itself.
    #
    # ## Example
    #
    #     "    foo\n  bar".dedent(2) #=> "  foo\nbar"
    #
    def dedent(n)
        gsub!(/^ {#{n}}/, "")
        self
    end

    ##
    # Indent all lines except the first by _n_ spaces in-place, and then return
    # itself.
    #
    # ## Example
    #
    #     "foo\nbar\nbaz".indent(4) #=> "foo\n    bar\n    baz"
    def indent(n)
        gsub!(/(?!\A)^/, " " * n)
        self
    end
end

##
# Some utility methods for classes.
class Class
    ##
    # Register a new JavaType to be search for this regular expression when
    # using `JavaType#encode`.
    #
    # ## Example
    #
    #     class MyJavaType < JavaType
    #         register_java_type(/\Acom\.example\.MyType\z/)
    #         ...
    #     end
    #
    def register_java_type(regex)
        JavaType::REGISTRY << [regex, self]
    end
end

#}}}


#{{{ Utility methods

# Find the path to a Java source file given the class name.
#
# * `typename` --- The fully-qualified name of the type e.g.
#   `com.example.MyType`. Nested class is not yet supported.
# * `prefix` --- A Pathname of the project's directory. It is assumed that all
#   Java source can be found in `prefix/src`, e.g. the Java source for MyType
#   above should be found in `prefix/src/com/example/MyType.java`.
# * `package` --- The current package name, e.g. `com.example`. This is used to
#   find the exact name of an unqualified type.
# * `ext` --- The file extension of the path.
#
# ## Example
#
#     prefix = Pathname.new("/project/")
#     typename_to_path("MyType", prefix, "com.example")               #=> "/project/src/com/example/MyType.java"
#     typename_to_path("com.example2.MyType2", prefix, "com.example") #=> "/project/src/com/example2/MyType2.java"
#
def typename_to_path(typename, prefix, package, ext=".java")
    filename = typename.gsub(".", "/") << ext
    path = prefix.join("src", filename)
    if path.exist?
        path
    else
        prefix.join("src", package.gsub(".", "/"), filename)
    end
end


unless defined?(PARCELABLE_TYPES)
    KNOWN_PARCELABLES_FN = File.join(File.dirname(__FILE__), "known_parcelables.txt")
    PARCELABLE_TYPES = Set.new(File.readlines(KNOWN_PARCELABLES_FN).each(&:chomp!))
end

##
# Check if a type is Parcelable, Serializable or an IInterface.
def get_interface_class(typename, prefix, package, imports)
    fq_typename = typename
    check_typename = "." << typename
    imports.each do |type, qname|
        if qname == typename || qname.end_with?(check_typename)
            fq_typename = qname
            if type != :import
                return type
            else
                break
            end
        end
    end

    if PARCELABLE_TYPES.include?(fq_typename)
        :parcelable
    elsif typename_to_path(fq_typename, prefix, package).exist?
        :parcelable
    else
        :interface
    end
end


##
# Get the variable name of the Parcelable.Creator for a Java type.
def get_creator_var(typename)
    case typename
    when "java.lang.CharSequence", "CharSequence"
        "android.text.TextUtils.CHAR_SEQUENCE_CREATOR"
    else
        "#{typename}.CREATOR"
    end
end

##
# Get the flag in `writeParcelable` for a parcel name.
def get_parcelable_flag(parcel)
    if parcel == "reply"
        "android.os.Parcelable.PARCELABLE_WRITE_RETURN_VALUE"
    else
        "0"
    end
end

#}}}

##
# Indicates a Java type.
#
# ## Example
#
#     arg = AIDL2Argument.new(:out, "List<String>", "foo", 0, nil)
#     JavaType.encode(:transact, :post, arg, "_arg0", writer) #=> "reply.readStringList(_arg0);"
#
class JavaType
    REGISTRY = [] # :nodoc:

    PARCEL_NAMES = { # :nodoc:
        [:proxy, :pre] => "_data",
        [:proxy, :post] => "_reply",
        [:transact, :pre] => "data",
        [:transact, :post] => "reply",
    }

    METHOD_NAMES = { # :nodoc:
        [:proxy, :in, :pre] => :write_to_parcel,
        [:proxy, :in, :post] => nil,
        [:proxy, :out, :pre] => :write_buffer_info,
        [:proxy, :out, :post] => :read_from_parcel,
        [:proxy, :inout, :pre] => :write_to_parcel,
        [:proxy, :inout, :post] => :read_from_parcel,
        [:proxy, :return, :pre] => nil,
        [:proxy, :return, :post] => :create_from_parcel,
        [:transact, :in, :pre] => :create_from_parcel,
        [:transact, :in, :post] => nil,
        [:transact, :out, :pre] => :create_buffer,
        [:transact, :out, :post] => :write_to_parcel,
        [:transact, :inout, :pre] => :create_from_parcel,
        [:transact, :inout, :post] => :write_to_parcel,
        [:transact, :return, :pre] => nil,
        [:transact, :return, :post] => :write_to_parcel,
    }

    ##
    # Encode the argument into Java code which process conversion with a Parcel.
    #
    # * `transact_proxy` --- Whether the Java code is used in the `onTransact()`
    #   method (`:transact`) or in the Proxy class (`:proxy`).
    # * `pre_post` --- Whether the code appears before (`:pre`) or after
    #   (`:post`) the real function call.
    # * `arg` --- An AIDL2Argument.
    # * `name` --- The variable name.
    # * `writer` --- A JavaWriter to determine the current environment.
    public
    def self.encode(transact_proxy, pre_post, arg, name, writer)
        if arg.java_type.nil?
            REGISTRY.reverse_each do |regex, cls|
                if regex =~ arg.type
                    arg.java_type = cls.new(arg, writer)
                    break
                end
            end
        end
        arg.java_type.do_encode(transact_proxy, pre_post, name)
    end

    private
    def initialize(arg, writer)
        @arg = arg
        @tokens = writer.tokens
        @writer = writer
    end

    public
    def do_encode(transact_proxy, pre_post, name)
        method_name = METHOD_NAMES[[transact_proxy, @arg.direction, pre_post]]
        if method_name.nil?
            ""
        else
            parcel = PARCEL_NAMES[[transact_proxy, pre_post]]
            send(method_name, parcel, name)
        end
    end

    ##
    # Raise an exception indicating the type cannot be marshalled in the given
    # direction.
    protected
    def do_raise
        error_message = "Cannot marshall '#{@arg.direction} #{@arg.type}'."
        ParseError.do_raise error_message, @tokens, @arg.p
    end

    ##
    # Create the Java code which creates a new instance of the type from a
    # parcel. The code should assume a `final Type var` before the code.
    protected
    def create_from_parcel(parcel, name)
        do_raise
    end

    ##
    # Create the Java code which writes an instance of the type to a parcel.
    protected
    def write_to_parcel(parcel, name)
        do_raise
    end

    ##
    # Create the Java code which modifies an existing instance of the type using
    # information in the parcel.
    protected
    def read_from_parcel(parcel, name)
        do_raise
    end

    ##
    # Create the Java code which construct a placeholder object for future
    # changes.
    protected
    def create_buffer(parcel, name)
        do_raise
    end

    ##
    # Create the Java code transmits information to the remote side to give more
    # precise information about how to construct the placeholder object.
    #
    # The default implementation does nothing.
    protected
    def write_buffer_info(parcel, name)
        ""
    end
end


#{{{ Subclasses

##
# Handles generic Java types.
class GenericJavaType < JavaType # :nodoc:
    register_java_type(/\A/)

    def initialize(arg, writer)
        super(arg, writer)
        @interface_class = get_interface_class(@arg.type, @writer.prefix,
                                               @writer.package, @writer.imports)
        @creator = get_creator_var(@arg.type)
    end

    def create_from_parcel(parcel, name)
        case @interface_class
        when :parcelable
            ";
            if (#{parcel}.readInt() != 0) {
                #{name} = #{@creator}.createFromParcel(#{parcel});
            } else {
                #{name} = null;
            }".dedent(12)
        when :interface
            " = #{@arg.type}.Stub.asInterface(#{parcel}.readStrongBinder());"
        when :serializable
            " = (#{@arg.type}) #{parcel}.readSerializable();"
        end
    end

    def write_to_parcel(parcel, name)
        case @interface_class
        when :parcelable
            "if (#{name} != null) {
                #{parcel}.writeInt(1);
                #{name}.writeToParcel(#{parcel}, #{get_parcelable_flag(parcel)});
            } else {
                #{parcel}.writeInt(0);
            }".dedent(12)
        when :interface
            "#{parcel}.writeStrongInterface(#{name});"
        when :serializable
            "#{parcel}.writeSerializable(#{name});"
        end
    end

    def read_from_parcel(parcel, name)
        case @interface_class
        when :parcelable
            "if (#{parcel}.readInt() != 0) {
                #{name}.readFromParcel(#{parcel});
            }".dedent(12)
        else
            do_raise
        end
    end

    def create_buffer(parcel, name)
        case @interface_class
        when :parcelable, :serializable
            " = new #{@arg.type}();"
        else
            do_raise
        end
    end
end


##
# Handles primitive Java types (`int`, `String`, etc.). These types cannot be
# used in an `out` argument.
class PrimitiveJavaType < JavaType # :nodoc:
    register_java_type(/\A(?:
        byte|double|float|int|long|
        (?:java\.io\.)?Serializable|
        (?:java\.lang\.)?String|
        (?:android\.os\.)?IBinder
    )\z/x)

    def initialize(arg, writer)
        super(arg, writer)
        @method_name = arg.type[/[^.]+\z/].capitalize
        @method_name = "StrongBinder" if @method_name == "Ibinder"
    end

    def create_from_parcel(parcel, name)
        " = #{parcel}.read#{@method_name}();"
    end

    def write_to_parcel(parcel, name)
        "#{parcel}.write#{@method_name}(#{name});"
    end
end


##
# Handles Java types which must be coerced to an `int` in the Parcel.
class IntLikeJavaType < JavaType # :nodoc:
    register_java_type(/\A(?:char|short)\z/)

    def create_from_parcel(parcel, name)
        " = (#{@arg.type}) #{parcel}.readInt();"
    end

    def write_to_parcel(parcel, name)
        "#{parcel}.writeInt(#{name});"
    end
end


##
# Handles generic arrays (`T[]`).
class GenericArrayJavaType < JavaType # :nodoc:
    register_java_type(/\[\]\z/)

    def initialize(arg, writer)
        super(arg, writer)
        @creator = get_creator_var(@arg.type[0...-2])
    end

    def create_from_parcel(parcel, name)
        " = #{parcel}.createTypedArray(#{@creator});"
    end

    def write_to_parcel(parcel, name)
        "#{parcel}.writeTypedArray(#{name}, #{get_parcelable_flag(parcel)});"
    end

    def read_from_parcel(parcel, name)
        "#{parcel}.readTypedArray(#{name}, #{@creator});"
    end

    def write_buffer_info(parcel, name)
        "#{parcel}.writeInt((#{name} != null) ? #{name}.length : -1);"
    end

    def create_buffer(parcel, name)
        ";
        final int _length_#{name} = #{parcel}.readInt();
        if (_length_#{name} >= 0) {
            #{name} = new #{@arg.type[0...-2]}[_length_#{name}];
        } else {
            #{name} = null;
        }".dedent(8)
    end
end


##
# Handles primitive arrays (`int[]`, `char[]`, `String[]`, etc.).
class PrimitiveArrayJavaType < GenericArrayJavaType # :nodoc:
    register_java_type(/\A(?:
        boolean|byte|char|double|float|int|long|
        (?:java\.lang\.)?String|
        (?:android\.os\.)?IBinder
    )\[\]\z/x)

    def initialize(arg, writer)
        super(arg, writer)
        @method_name = arg.type[/[^.\[]+(?=\[)/].capitalize
        @method_name = "Binder" if @method_name == "Ibinder"
    end

    def create_from_parcel(parcel, name)
        " = #{parcel}.create#{@method_name}Array();"
    end

    def write_to_parcel(parcel, name)
        "#{parcel}.write#{@method_name}Array(#{name});"
    end

    def read_from_parcel(parcel, name)
        "#{parcel}.read#{@method_name}Array(#{name});"
    end
end


module CreateArrayListMixin
    def create_buffer(parcel, name)
        " = new #{@arg.type.sub(/\A(?:java\.util\.)?List/, "java.util.ArrayList")}();"
    end
end


##
# Handles generic lists (`List<T>`).
class GenericListJavaType < JavaType # :nodoc:
    register_java_type(/\A(?:java\.util\.)?(?:Array)?List<.+>\z/m)

    def initialize(arg, writer)
        super(arg, writer)
        /<(.+)>\z/ =~ @arg.type
        @content_type = $1
        @interface_class = get_interface_class(@content_type, @writer.prefix,
                                               @writer.package, @writer.imports)
        @creator = get_creator_var(@content_type)
    end

    def create_from_parcel(parcel, name)
        case @interface_class
        when :parcelable
            " = #{parcel}.createTypedArrayList(#{@creator})"
        when :interface
            ";
            final java.util.ArrayList<android.os.IBinder> _binderProxies_#{name} = #{parcel}.createBinderArrayList();
            if (_binderProxies_#{name} != null) {
                final int _size_#{name} = _binderProxies_#{name}.size();
                #{name}#{create_buffer(parcel, name)[0...-3]}(_size_#{name});
                for (final android.os.IBinder _binder_#{name} : _binderProxies_#{name}) {
                    #{name}.add(#{@content_type}.Stub.asInterface(_binder_#{name}));
                }
            } else {
                #{name} = null;
            }".dedent(12)
        when :serializable
            ";
            final int _size_#{name} = #{parcel}.readInt();
            if (_size_#{name} >= 0) {
                #{name} = new java.util.ArrayList<#{@content_type}>(_size_#{name});
                for (int _i_#{name} = 0; _i_#{name} < _size_#{name}; ++ _i_#{name}) {
                    #{name}.add((#{@content_type}) #{parcel}.readSerializable());
                }
            } else {
                #{name} = null;
            }".dedent(12)
        end
    end

    def write_to_parcel(parcel, name)
        case @interface_class
        when :parcelable
            "#{parcel}.writeTypedArrayList(#{name});"
        when :interface
            "final int _writeSize_#{name} = #{name}.size();
            final java.util.ArrayList<android.os.IBinder> _realBinders_#{name} = new java.util.ArrayList<android.os.IBinder>(_writeSize_#{name});
            for (final android.os.IInterface _interface_#{name} : #{name}) {
                _realBinders_#{name}.add(_interface_#{name} != null ? _interface_#{name}.asBinder() : null);
            }
            #{parcel}.writeBinderList(_realBinders_#{name});".dedent(12)
        when :serializable
            "if (#{name} != null) {
                #{parcel}.writeInt(#{name}.size());
                for (final java.io.Serializable _item_#{name} : #{name}) {
                    #{parcel}.writeSerializable(_item_#{name});
                }
            } else {
                #{parcel}.writeInt(-1);
            }".dedent(12)
        end
    end

    def read_from_parcel(parcel, name)
        case @interface_class
        when :parcelable
            "#{parcel}.readTypedArrayList(#{name}, #{@creator});"
        when :interface
            "final java.util.ArrayList<android.os.IBinder> _binderProxies_#{name} = #{parcel}.createBinderArrayList();
            if (_binderProxies_#{name} != null) {
                #{name}.clear();
                for (final android.os.IBinder _binder_#{name} : _binderProxies_#{name}) {
                    #{name}.add(#{@content_type}.Stub.asInterface(_binder_#{name}));
                }
            }".dedent(12)
        when :serializable
            "final int _readSize_#{name} = #{parcel}.readInt();
            if (_readSize_#{name} >= 0) {
                #{name}.clear();
                for (int _i_#{name} = 0; _i_#{name} < _readSize_#{name}; ++ _i_#{name}) {
                    #{name}.add((#{@content_type}) #{parcel}.readSerializable());
                }
            }".dedent(12)
        end
    end

    include CreateArrayListMixin
end


##
# Handles primitive lists (`List<String>`, etc.).
class PrimitiveListJavaType < JavaType # :nodoc:
    register_java_type(/\A
        (?:java\.util\.)?(?:Array)?List<\s*(?:
            (?:java\s*\.\s*lang\s*\.\s*)?String|
            (?:android\s*\.\s*os\s*\.\s*)?IBinder
        )\s*>\z
    /x)

    def initialize(arg, writer)
        super(arg, writer)
        @method_name = @arg.type[/[^.<\s]+(?=\s*>)/]
        @method_name = "Binder" if @method_name == "IBinder"
    end

    def create_from_parcel(parcel, name)
        " = #{parcel}.create#{@method_name}ArrayList();"
    end

    def write_to_parcel(parcel, name)
        "#{parcel}.write#{@method_name}List(#{name});"
    end

    def read_from_parcel(parcel, name)
        "#{parcel}.read#{@method_name}List(#{name});"
    end

    include CreateArrayListMixin
end


##
# Handles untyped collections (`List` and `Map`). These types should not really
# be used.
class UntypedCollectionJavaType < JavaType # :nodoc:
    register_java_type(/\A(?:java\.util\.)?(?:(?:Array)?List|(?:Hash)?Map)\z/x)

    def initialize(arg, writer)
        super(arg, writer)
        if @arg.type.include?("List")
            @method_names = ["List", "ArrayList"]
        else
            @method_names = ["Map", "HashMap"]
        end
    end

    def create_from_parcel(parcel, name)
        " = #{parcel}.read#{@method_names[1]}(getClass().getClassLoader());"
    end

    def write_to_parcel(parcel, name)
        "#{parcel}.write#{@method_names[0]}(#{name});"
    end

    def read_from_parcel(parcel, name)
        "#{parcel}.read#{@method_names[0]}(#{name}, getClass().getClassLoader());"
    end

    def create_buffer(parcel, name)
        " = new java.util.#{method_names[1]}();"
    end
end


##
# Handles the SparseBooleanArray Java type.
class SparseBooleanArrayJavaType < JavaType # :nodoc:
    register_java_type(/\A(?:android\.os\.)?SparseBooleanArray\z/x)

    def create_from_parcel(parcel, name)
        " = #{parcel}.readSparseBooleanArray();"
    end

    def write_to_parcel(parcel, name)
        "#{parcel}.writeSparseBooleanArray(#{name});"
    end

    def read_from_parcel(parcel, name)
        # TODO find way to invoke .readSparseBooleanArrayInternal() instead.
        "#{name}.clear();
        final android.os.SparseBooleanArray _array_#{name} = #{parcel}.readSparseBooleanArray();
        final int _size_#{name} = _array_#{name}.size();
        for (int _i_#{name} = 0; _i_#{name} < _s_#{name}; ++ _i_#{name}) {
            final int _key_#{name} = _array_#{name}.keyAt(_i_#{name});
            final boolean _value_#{name} = _array_#{name}.valueAt(_i_#{name});
            #{name}.append(_key_#{name}, _value_#{name});
        }".dedent(8)
    end

    def create_buffer(parcel, name)
        " = new android.os.SparseBooleanArray();"
    end
end

#}}}

