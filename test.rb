require 'test/unit'
require 'lexer.rl'
require 'parser.rl'

TEST_INPUT = <<EOF
package com.example.test;

/* Comment */
import java.util.List; // Line comment

/** Javadoc
// Line comment inside Javadoc
*/
mainthread localthrow interface Bar {
    List<String> transform(in List<? extends CharSequence> input);
    oneway void check(inout List<List<Integer>>[ ] input);
}
EOF

class TestTokenizer < Test::Unit::TestCase
    #{{{
    def test_basic
        token_list = Tokenizer.tokenize(TEST_INPUT)

        assert_equal([
            :package, 'com', '.', 'example', '.', 'test', ';',
            :import, 'java', '.', 'util', '.', 'List', ';',
            "/** Javadoc\n// Line comment inside Javadoc\n*/",
            :mainthread, :localthrow, :interface, 'Bar', '{',
            'List', '<String>', 'transform',
                '(', :in, 'List', '<? extends CharSequence>', 'input', ')', ';',
            :oneway, 'void', 'check',
                '(', :inout, 'List', '<List<Integer>>', '[', ']', 'input', ')', ';',
            '}'
        ], token_list.tokens)

        assert_equal('pn.n.n;on.n.n;jmmin{ngn(dngn);mnn(dng[]n);}', token_list.types)
    end

    def test_unbalanced_generic
        assert_raise ParseError do
            Tokenizer.tokenize('List<<')
        end
    end

    def test_unknown_char
        assert_raise ParseError do
            Tokenizer.tokenize(">")
        end
    end

    def test_run_away_comment
        assert_raise ParseError do
            Tokenizer.tokenize('eee /* unfinished comment')
        end
    end

    def test_run_away_java_doc
        assert_raise ParseError do
            Tokenizer.tokenize('/** unfinished javadoc')
        end
    end

    def test_single_line_comment_at_end
        token_list = Tokenizer.tokenize('// test')
        assert_equal([], token_list.tokens)
        assert_equal('', token_list.types)
    end
    #}}}
end

class TestParser < Test::Unit::TestCase
    def test_parse
        token_list = Tokenizer.tokenize(TEST_INPUT)
        Parser.parse(token_list)
    end
end

