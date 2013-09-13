#!/usr/bin/ruby -w

AIDL2Argument = Struct.new(:direction, :type, :name, :p, :java_type) do
    def void?
        type == "void"
    end
end

AIDL2Method = Struct.new(:javadoc, :modifiers, :name, :p, :ret, :arguments, :i)

AIDL2Interface = Struct.new(:javadoc, :modifiers, :name, :p, :methods, :package,
                            :imports, :tokens)

IMPORT_TYPES = {?o => :import, ?f => :parcelable, ?s => :serializable}

%%{
    machine parser;

    action mark_qname_start { qname_start = p }
    action store_qname { qname = token_list.join(qname_start, p) }
    action store_package_name { package_name = qname }

    action mark_import_type { import_type = IMPORT_TYPES[fc] }
    action append_import { imports << [import_type, qname] }

    action append_modifier { modifiers << token_list.tokens[p] }
    action store_javadoc { javadoc = token_list.tokens[p] }
    action store_direction { direction = token_list.tokens[p] }
    action reset_modifiers_and_javadoc {
        modifiers = interface_modifiers.dup
        javadoc = nil
    }

    action mark_type_name_start { type_name_start = p }
    action store_type_name { type_name = token_list.join(type_name_start, p) }

    action reset_direction { direction = :in }
    action store_arg_name { arg_name_p = p }
    action append_argument {
        args << AIDL2Argument.new(direction, type_name,
                                  token_list.tokens[arg_name_p], arg_name_p, nil)
    }
    action reset_arguments { args = [] }

    action store_return_type { return_type = type_name }
    action store_method_name { method_name_p = p }
    action append_method {
        ret = AIDL2Argument.new(:return, return_type, nil, method_name_p, nil)
        method = AIDL2Method.new(javadoc, modifiers,
                                 token_list.tokens[method_name_p],
                                 method_name_p, ret, args, methods.length)
        methods << method
    }

    action store_interface_modifiers_and_javadoc {
        interface_javadoc = javadoc
        interface_modifiers = modifiers
    }
    action store_interface_name { interface_name_p = p }

    qualified = ('n' ('.n')*) >mark_qname_start %store_qname;
    package = 'p' qualified ';' @store_package_name;
    import_ = [ofs] >mark_import_type qualified ';' @append_import;

    modifier = 'm' @append_modifier;
    javadoc = 'j' @store_javadoc;
    direction = 'd' @store_direction;

    entity_prefix = (javadoc? modifier*) >reset_modifiers_and_javadoc;

    type = (qualified 'g'? ('[]')*) >mark_type_name_start %store_type_name;

    arg = (direction? type 'n' @store_arg_name) >reset_direction %append_argument;
    arg_list = (arg (',' arg)*)? >reset_arguments;

    method = entity_prefix type %store_return_type
             'n' @store_method_name '(' arg_list ');' @append_method;

    interface = entity_prefix %store_interface_modifiers_and_javadoc
                'in' @store_interface_name '{' method* '}';

    main := package import_* interface?;
}%%


class Parser
    %% write data;

    def self.parse(token_list)
        data = token_list.types

        imports = []
        interface_modifiers = []
        modifiers = []
        javadoc = nil
        args = []
        methods = []
        type_name = nil
        arg_name_p = nil
        method_name_p = nil
        return_type = nil
        package_name = nil
        direction = :in
        import_type = :import
        interface_name_p = nil

        %% write init;
        %% write exec;

        if p < data.length || cs < %%{ write first_final; }%%
            ParseError.do_raise 'Failed to parse', token_list, p
        end

        if interface_name_p.nil?
            nil
        else
            interface_name = token_list.tokens[interface_name_p]
            AIDL2Interface.new(interface_javadoc, interface_modifiers,
                               interface_name, interface_name_p, methods,
                               package_name, imports, token_list)
        end
    end
end

