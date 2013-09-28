#!/usr/bin/ruby -w

GenericParameter = Struct.new(:name, :extends)

%%{
    machine generic;

    action mark_name_begin { name_begin = p }
    action mark_name_end { name_end = p }
    action mark_type_begin { type_begin = p }
    action mark_type_end { type_end = p }

    action push_extends {
        type = data[type_begin...p]
        type.strip!
        type.gsub!(/\s*(\W)\s*/, '\1')
        extends << type
    }

    action push_param {
        name = data[name_begin...name_end]
        parameters << GenericParameter.new(name, extends)
        extends = []
    }

    open = '<' @{ generic_depth += 1 };
    close = ('>' when { generic_depth > 0 }) @{ generic_depth -= 1 };
    last_close = ('>' when { generic_depth <= 0 });
    gen_cnt = [^<>] | open | close;
    generic = '<' gen_cnt* last_close space*;

    typename = ([^,<>&]+ generic?) >mark_type_begin %push_extends;
    typelist = typename ('&' typename)*;

    ident_char = [a-zA-Z0-9_];
    ident = ident_char+;

    param = ident >mark_name_begin %mark_name_end space*
            (space ident typelist)?
            [,>] @push_param;

    main := '<' space* param (space* param)*;
}%%

class GenericParser
    %% write data;

    def self.parse(data)
        eof = data.length
        generic_depth = 0
        parameters = []
        extends = []

        %% write init;

        %% write exec;

        if p < data.length || cs < %%{ write first_final; }%%
            ParseError.do_raise_lex "Invalid generic parameters", "(?)", data, p
        end

        parameters
    end
end

