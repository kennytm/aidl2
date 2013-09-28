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


$ident_index = 0

def alloc_index
    $ident_index += 1
end

def reset_index
    $ident_index = 0
end

def gi(sym)
    if $ident_index == 1
        "_#{sym}"
    else
        "_#{sym}#{$ident_index}"
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
def get_interface_class(typename, writer)
    fq_typename = typename
    check_typename = "." << typename
    writer.imports.each do |type, qname|
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
    elsif typename_to_path(fq_typename, writer.prefix, writer.package).exist?
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

##
# Remove the generics part of the type name.
def remove_generics(typename)
    typename[/\A[^<]*/]
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
            the_type = arg.type
            writer.generic.each do |gp|
                if arg.type == gp.name
                    the_type = gp.extends[0] || 'java.lang.Object'
                    break
                end
            end
            REGISTRY.reverse_each do |regex, cls|
                if regex =~ the_type
                    arg.java_type = cls.new(arg, the_type, writer)
                    break
                end
            end
        end
        arg.java_type.do_encode(transact_proxy, pre_post, name)
    end

    private
    def initialize(arg, repr_type, writer)
        @arg = arg
        @repr_type = repr_type
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

    def initialize(arg, repr_type, writer)
        super(arg, repr_type, writer)
        raw_type = remove_generics(repr_type)
        @interface_class = get_interface_class(raw_type, @writer)
        @creator = get_creator_var(raw_type)
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
            " = #{remove_generics(@repr_type)}.Stub.asInterface(#{parcel}.readStrongBinder());"
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
            " = new #{@repr_type}();"
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

    def initialize(arg, repr_type, writer)
        super(arg, repr_type, writer)
        @method_name = repr_type[/[^.]+\z/].capitalize
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


class BooleanJavaType < JavaType # :nodoc:
    register_java_type(/\Aboolean\z/)

    def create_from_parcel(parcel, name)
        " = (#{parcel}.readInt() != 0);"
    end

    def write_to_parcel(parcel, name)
        "#{parcel}.writeInt(#{name} ? 1 : 0);"
    end
end


##
# Handle UUID types.
class UUIDJavaType < JavaType # :nodoc:
    register_java_type(/\A(?:java\.util\.)?UUID\z/)

    def create_from_parcel(parcel, name)
        alloc_index
        ";
        if (#{parcel}.readInt() != 0) {
            final long #{gi:msb} = #{parcel}.readLong();
            final long #{gi:lsb} = #{parcel}.readLong();
            #{name} = new java.util.UUID(#{gi:msb}, #{gi:lsb});
        } else {
            #{name} = null;
        }".dedent(8)
    end

    def write_to_parcel(parcel, name)
        "if (#{name} != null) {
            #{parcel}.writeInt(1);
            #{parcel}.writeLong(#{name}.getMostSignificantBits());
            #{parcel}.writeLong(#{name}.getLeastSignificantBits());
        } else {
            #{parcel}.writeInt(0);
        }".dedent(8)
    end
end


##
# Handle Parcelable types.
class ParcelableJavaType < JavaType # :nodoc:
    register_java_type(/\A(?:android\.os\.)?Parcelable\z/)

    def create_from_parcel(parcel, name)
        " = #{parcel}.readParcelable(getClass().getClassLoader());"
    end

    def write_to_parcel(parcel, name)
        "#{parcel}.writeParcelable(#{name}, #{get_parcelable_flag(parcel)});"
    end
end


##
# Handle Object types.
class ObjectJavaType < JavaType # :nodoc:
    register_java_type(/\A(?:java\.lang\.)?Object\z/)

    def create_from_parcel(parcel, name)
        " = (#{@arg.type}) #{parcel}.readValue(getClass().getClassLoader());"
    end

    def write_to_parcel(parcel, name)
        "#{parcel}.writeValue(#{name});"
    end
end


##
# Handles generic arrays (`T[]`).
class GenericArrayJavaType < JavaType # :nodoc:
    register_java_type(/\[\]\z/)

    def initialize(arg, repr_type, writer)
        super(arg, repr_type, writer)
        @creator = get_creator_var(remove_generics(repr_type[0...-2]))
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
        alloc_index
        ";
        final int #{gi:length} = #{parcel}.readInt();
        if (#{gi:length} >= 0) {
            #{name} = new #{@repr_type[0...-2]}[#{gi:length}];
        } else {
            #{name} = null;
        }".dedent(8)
    end
end


def read_uuid_list_common(parcel, initializer, setter)
    "final long[] #{gi:bits} = #{parcel}.createLongArray();
    if (#{gi:bits} != null) {
        final boolean #{gi:hasNull} = (#{parcel}.readInt() != 0);
        long #{gi:nullMsb} = 0;
        long #{gi:nullLsb} = 0;
        if (#{gi:hasNull}) {
            #{gi:nullMsb} = #{parcel}.readLong();
            #{gi:nullLsb} = #{parcel}.readLong();
        }
        final int #{gi:length} = #{gi:bits}.length / 2;
        #{initializer}
        for (int #{gi:i} = 0, #{gi:j} = 0; #{gi:i} < #{gi:length}; ++ #{gi:i}) {
            final long #{gi:msb} = #{gi:bits}[#{gi:j}++];
            final long #{gi:lsb} = #{gi:bits}[#{gi:j}++];
            final java.util.UUID #{gi:uuid};
            if (#{gi:hasNull} && #{gi:msb} == #{gi:nullMsb} && #{gi:lsb} == #{gi:nullLsb}) {
                #{gi:uuid} = null;
            } else {
                #{gi:uuid} = new java.util.UUID(#{gi:msb}, #{gi:lsb});
            }
            #{setter}
        }
    }".dedent(4)
end


def write_uuid_list_common(parcel, name, length_member, to_list)
    "if (#{name} != null) {
        final long[] #{gi:bits} = new long[#{name}.#{length_member} * 2];
        java.util.UUID #{gi:nullUuid} = null;
        int #{gi:i} = 0;
        for (java.util.UUID #{gi:uuid} : #{name}) {
            if (#{gi:uuid} == null) {
                if (#{gi:nullUuid} == null) {
                    do {
                        #{gi:nullUuid} = java.util.UUID.randomUUID();
                    } while (#{to_list}.contains(#{gi:nullUuid}));
                }
                #{gi:uuid} = #{gi:nullUuid};
            }
            #{gi:bits}[#{gi:i}++] = #{gi:uuid}.getMostSignificantBits();
            #{gi:bits}[#{gi:i}++] = #{gi:uuid}.getLeastSignificantBits();
        }
        #{parcel}.writeLongArray(#{gi:bits});
        if (#{gi:nullUuid} != null) {
            #{parcel}.writeInt(1);
            #{parcel}.writeLong(#{gi:nullUuid}.getMostSignificantBits());
            #{parcel}.writeLong(#{gi:nullUuid}.getLeastSignificantBits());
        } else {
            #{parcel}.writeInt(0);
        }
    } else {
        #{parcel}.writeLongArray(null);
    }".dedent(4)
end


##
# Handles array of UUID.
class UUIDArrayJavaType < GenericArrayJavaType # :nodoc:
    register_java_type(/(?:java\.util\.)?UUID\[\]\z/)

    def create_from_parcel(parcel, name)
        alloc_index
        initializer = "#{name} = new java.util.UUID[#{gi:length}];"
        setter = "#{name}[#{gi:i}] = #{gi:uuid};"
        res = ";\n#{read_uuid_list_common(parcel, initializer, setter)} else {\n"
        res << "    #{name} = null;\n}"
        res
    end

    def write_to_parcel(parcel, name)
        alloc_index
        write_uuid_list_common(parcel, name, "length", "java.util.Arrays.asList(#{name})")
    end

    def read_from_parcel(parcel, name)
        alloc_index
        initializer = ""
        setter = "if (#{gi:i} < #{name}.length) {
            #{name}[#{gi:i}] = #{gi:uuid};
        }"
        read_uuid_list_common(parcel, initializer, setter)
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

    def initialize(arg, repr_type, writer)
        super(arg, repr_type, writer)
        @method_name = repr_type[/[^.\[]+(?=\[)/].capitalize
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
        " = new #{@repr_type.sub(/\A(?:java\.util\.)?List/, "java.util.ArrayList")}();"
    end
end


##
# Handles generic lists (`List<T>`).
class GenericListJavaType < JavaType # :nodoc:
    register_java_type(/\A(?:java\.util\.)?(?:Array)?List<.+>\z/m)

    def initialize(arg, repr_type, writer)
        super(arg, repr_type, writer)
        /<(.+)>\z/ =~ repr_type
        @content_type = $1
        raw_content_type = remove_generics(@content_type)
        @interface_class = get_interface_class(raw_content_type, @writer)
        @creator = get_creator_var(raw_content_type)
    end

    def create_from_parcel(parcel, name)
        case @interface_class
        when :parcelable
            " = #{parcel}.createTypedArrayList(#{@creator});"
        when :interface
            alloc_index
            ";
            final java.util.ArrayList<android.os.IBinder> #{gi:binders} = #{parcel}.createBinderArrayList();
            if (#{gi:binders} != null) {
                final int #{gi:size} = #{gi:binders}.size();
                #{name}#{create_buffer(parcel, name)[0...-3]}(#{gi:size});
                for (final android.os.IBinder #{gi:binder} : #{gi:binders}) {
                    #{name}.add(#{remove_generics(@content_type)}.Stub.asInterface(#{gi:binder}));
                }
            } else {
                #{name} = null;
            }".dedent(12)
        when :serializable
            alloc_index
            ";
            final int #{gi:size} = #{parcel}.readInt();
            if (#{gi:size} >= 0) {
                #{name} = new java.util.ArrayList<#{@content_type}>(#{gi:size});
                for (int #{gi:i} = 0; #{gi:i} < #{gi:size}; ++ #{gi:i}) {
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
            "#{parcel}.writeTypedList(#{name});"
        when :interface
            alloc_index
            "final int #{gi:size} = #{name}.size();
            final java.util.ArrayList<android.os.IBinder> #{gi:binders} = new java.util.ArrayList<android.os.IBinder>(#{gi:size});
            for (final android.os.IInterface #{gi:interface} : #{name}) {
                #{gi:binders}.add(#{gi:interface} != null ? #{gi:interface}.asBinder() : null);
            }
            #{parcel}.writeBinderList(#{gi:binders});".dedent(12)
        when :serializable
            alloc_index
            "if (#{name} != null) {
                #{parcel}.writeInt(#{name}.size());
                for (final java.io.Serializable #{gi:item} : #{name}) {
                    #{parcel}.writeSerializable(#{gi:item});
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
            alloc_index
            "final java.util.ArrayList<android.os.IBinder> #{gi:binders} = #{parcel}.createBinderArrayList();
            if (#{gi:binders} != null) {
                #{name}.clear();
                for (final android.os.IBinder #{gi:binder} : #{gi:binders}) {
                    #{name}.add(#{remove_generics(@content_type)}.Stub.asInterface(#{gi:binder}));
                }
            }".dedent(12)
        when :serializable
            "final int #{gi:size} = #{parcel}.readInt();
            if (#{gi:size} >= 0) {
                #{name}.clear();
                for (int #{gi:i} = 0; #{gi:i} < #{gi:size}; ++ #{gi:i}) {
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

    def initialize(arg, repr_type, writer)
        super(arg, repr_type, writer)
        @method_name = repr_type[/[^.<\s]+(?=\s*>)/]
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
# Handles list of UUID.
class UUIDListJavaType < JavaType # :nodoc:
    register_java_type(/\A
        (?:java\.util\.)?(?:Array)?List
        <\s*(?:java\s*\.\s*util\s*\.\s*)?UUID\s*>\z
    /x)

    def create_from_parcel(parcel, name)
        alloc_index
        initializer = "#{name} = new java.util.ArrayList<java.util.UUID>(#{gi:length});"
        setter = "#{name}.add(#{gi:uuid});"
        res = ";\n#{read_uuid_list_common(parcel, initializer, setter)} else {\n"
        res << "    #{name} = null;\n}"
        res
    end

    def write_to_parcel(parcel, name)
        alloc_index
        write_uuid_list_common(parcel, name, "size()", name)
    end

    def read_from_parcel(parcel, name)
        alloc_index

        initializer = "final int #{gi:curSize} = #{name}.size();
        if (#{gi:curSize} > #{gi:length}) {
            #{name}.subList(#{gi:length}, #{gi:curSize}).clear();
        }"

        setter = "if (#{gi:i} < #{gi:curSize}) {
            #{name}.set(#{gi:i}, #{gi:uuid});
        } else {
            #{name}.add(#{gi:uuid});
        }".indent(4)

        read_uuid_list_common(parcel, initializer, setter)
    end

    include CreateArrayListMixin
end


##
# Handles untyped collections (`List` and `Map`). These types should not really
# be used.
class UntypedCollectionJavaType < JavaType # :nodoc:
    register_java_type(/\A(?:java\.util\.)?(?:(?:Array)?List|(?:Hash)?Map)\z/x)

    def initialize(arg, repr_type, writer)
        super(arg, repr_type, writer)
        if repr_type.include?("List")
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
        alloc_index
        "#{name}.clear();
        final android.os.SparseBooleanArray #{gi:array} = #{parcel}.readSparseBooleanArray();
        final int #{gi:size} = #{gi:array}.size();
        for (int #{gi:i} = 0; #{gi:i} < #{gi:size}; ++ #{gi:i}) {
            final int #{gi:key} = #{gi:array}.keyAt(#{gi:i});
            final boolean #{gi:value} = #{gi:array}.valueAt(#{gi:i});
            #{name}.append(#{gi:key}, #{gi:value});
        }".dedent(8)
    end

    def create_buffer(parcel, name)
        " = new android.os.SparseBooleanArray();"
    end
end

#}}}

