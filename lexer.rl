#!/usr/bin/ruby -w

class ParseError < RuntimeError
    attr_reader :filename, :line, :column, :error

    def initialize(message, filename, line=1, column=1)
        @filename = filename
        @line = line
        @column = column
        @message = message
    end

    def to_s
        "#{@filename}:#{@line}:#{@column}: #{@message}"
    end

    def self.do_raise_lex(error, filename, data, index)
        # Find number of '\n' before the index to determine the line number.
        line_count = data[0...index].count("\n") + 1
        line_start_index = (data.rindex("\n", index) || -1) + 1
        line_end_index = data.index("\n", index) || data.length
        col_count = index - line_start_index + 1
        the_line = data[line_start_index...line_end_index]
        message = "%s\n\n    %s\n    %*s\n" % [error, the_line, col_count, '^']
        raise ParseError.new(message, filename, line_count, col_count)
    end

    def self.do_raise(error, token_list, token_index)
        index = token_list.indices[token_index] || token_list.data.length
        self.do_raise_lex error, token_list.filename, token_list.data, index
    end
end


%%{
    machine lexer;

    direction = 'in' | 'out' | 'inout';
    modifier = 'oneway' | 'mainthread' | 'localthrow' | 'logtransaction';

    generic_open = '<' @{ generic_depth += 1 };
    generic_char = ([^<>]
                    | generic_open
                    | '>' @{ generic_depth -= 1 }) when { generic_depth > 0 };

    main := |*
        'package' => { add_kw_token.call 'p' };
        'import' => { add_kw_token.call 'o' };
        'interface' => { add_kw_token.call 'i' };
        'parcelable' => { add_kw_token.call 'f' };
        'serializable' => { add_kw_token.call 's' };
        direction => { add_kw_token.call 'd' };
        modifier => { add_kw_token.call 'm' };
        [.;,\[\]{}()] => { add_symbol.call };
        generic_open generic_char+ => { add_token.call 'g' };
        [_0-9a-zA-Z?]+ => { add_token.call 'n' };
        '/**' any* :>> '*/' => { add_token.call 'j' };
        '/*' any* :>> '*/';
        '//' [^\n]*;
        space;
    *|;
}%%


TokenList = Struct.new(:data, :filename, :tokens, :types, :indices) do
    def join(from, to)
        tokens[from...to].join("")
    end
end

class Tokenizer
    %% write data;

    def self.tokenize(data, filename="(none)")
        tokens = []
        token_indices = []
        types = ""

        eof = :ignored
        generic_depth = 0
        %% write init;

        add_token = proc do |type|
            tokens << data[ts...te]
            token_indices << ts
            types << type
        end

        add_kw_token = proc do |type|
            tokens << data[ts...te].to_sym
            token_indices << ts
            types << type
        end

        add_symbol = proc do
            symbol = data[ts...te]
            tokens << symbol
            token_indices << ts
            types << symbol
        end

        %% write exec;

        if (te || p) < data.length || cs < %%{ write first_final; }%%
            ParseError.do_raise_lex 'Failed to tokenize', filename, data, ts
        end

        TokenList.new(data, filename, tokens, types, token_indices)
    end
end

