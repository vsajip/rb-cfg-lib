require 'stringio'

require 'test_helper'

def make_tokenizer(src)
  stream = StringIO.new src, 'r:utf-8'
  CFG::Config::Tokenizer.new stream
end

def make_token(kind, text, value, sline, scol, eline, ecol)
  spos = CFG::Config::Location.new sline, scol
  epos = CFG::Config::Location.new eline, ecol
  result = CFG::Config::Token.new kind, text, value
  result.start = spos
  result.end = epos
  result
end

def data_file_path(dfn)
  File.join File.expand_path('resources'), dfn
end

def load_data(path)
  result = {}
  f = File.open path, 'r:utf-8'
  key = nil
  value = []
  f.each do |line|
    m = /^-- ([A-Z]\d+) -+/.match line
    if m.nil?
      value.push line.rstrip
    else
      result[key] = value.join("\n") if !key.nil? && !value.empty?
      key = m[1]
      value.clear
    end
  end
  f.close
  result
end

class PackageTest < Minitest::Test
  def test_valid_version
    refute_nil CFG::Config::VERSION
  end
end

class LocationTest < Minitest::Test
  def test_location
    loc1 = CFG::Config::Location.new
    assert loc1.line == 1
    assert loc1.column == 1
    loc1.next_line
    loc1.next_line
    assert loc1.line == 3
    assert loc1.column == 1
    loc2 = CFG::Config::Location.new
    assert loc2.line == 1
    assert loc2.column == 1
    loc2.update loc1
    assert loc2.line == 3
    assert loc2.column == 1
    assert loc2.to_s == '(3, 1)'
    loc3 = CFG::Config::Location.from loc1
    assert loc3.line == 3
    assert loc3.column == 1
  end
end

class TokenTest < Minitest::Test
  def test_token
    t = CFG::Config::Token.new(:EOF, '')
    assert_equal 'Token(EOF, "", nil)', t.to_s
  end
end

class TokenizerTest < Minitest::Test
  def test_init
    t = CFG::Config::Tokenizer.new(nil)
    refute_nil t
  end

  def test_tokens
    cases = [
      ['', :EOF, '', nil, '(1, 1)'],
      ["# a comment\n", :NEWLINE, '# a comment', nil, '(2, 0)'],
      ['foo', :WORD, 'foo', 'foo', '(1, 3)'],
      ['`foo`', :BACKTICK, '`foo`', 'foo', '(1, 5)'],
      ["'foo'", :STRING, "'foo'", 'foo', '(1, 5)'],
      ['2.71828', :FLOAT, '2.71828', 2.71828, '(1, 7)'],
      ['.5', :FLOAT, '.5', 0.5, '(1, 2)'],
      ['-.5', :FLOAT, '-.5', -0.5, '(1, 3)'],
      ['0x123aBc', :INTEGER, '0x123aBc', 0x123abc, '(1, 8)'],
      ['0o123', :INTEGER, '0o123', 83, '(1, 5)'],
      ['0123', :INTEGER, '0123', 83, '(1, 4)'],
      ['0b0001_0110_0111', :INTEGER, '0b0001_0110_0111', 0x167, '(1, 16)'],
      ['1e8', :FLOAT, '1e8', 1e8, '(1, 3)'],
      ['1e-8', :FLOAT, '1e-8', 1e-8, '(1, 4)'],
      ['-4', :INTEGER, '-4', -4, '(1, 2)'],
      ['-4e8', :FLOAT, '-4e8', -4e8, '(1, 4)'],

      # empty strings
      ['""', :STRING, '""', '', '(1, 2)'],
      ["''", :STRING, "''", '', '(1, 2)'],
      ['""""""', :STRING, '""""""', '', '(1, 6)'],
      ["\"\"\"abc\ndef\n\"\"\"", :STRING, "\"\"\"abc\ndef\n\"\"\"", "abc\ndef\n", '(3, 3)']
      # ["""'\n'""", :STRING, """'\n'""", "\n", '(2, 1)']
    ]

    cases.each do |item|
      source, kind, text, value, ends = item
      tokenizer = make_tokenizer source
      t = tokenizer.get_token
      assert_equal kind, t.kind
      assert_equal text, t.text
      if !value.nil?
        assert_equal value, t.value
      else
        assert_nil t.value
      end
      assert_equal '(1, 1)', t.start.to_s
      assert_equal(ends, t.end.to_s) unless ends.nil?
      assert_equal :EOF, tokenizer.get_token.kind
    end

    tokenizer = make_tokenizer '9+4j+a*b'
    tokens = tokenizer.tokens
    kinds = tokens.map(&:kind)
    texts = tokens.map(&:text)
    values = tokens.map(&:value)
    assert_equal %i[INTEGER PLUS COMPLEX PLUS WORD STAR WORD EOF], kinds
    assert_equal ['9', '+', '4j', '+', 'a', '*', 'b', ''], texts
    assert_equal [9, nil, (0.0 + 4.0i), nil, 'a', nil, 'b', nil], values
    source = '< > { } [ ] ( ) + - * / ** // % . <= <> << >= >> == != , : @ ~ & | ^ $ && ||'
    tokenizer = make_tokenizer source
    tokens = tokenizer.tokens
    kinds = tokens.map(&:kind)
    texts = tokens.map(&:text)
    assert_equal %i[LESS_THAN GREATER_THAN LEFT_CURLY RIGHT_CURLY
                    LEFT_BRACKET RIGHT_BRACKET
                    LEFT_PARENTHESIS RIGHT_PARENTHESIS
                    PLUS MINUS STAR SLASH POWER SLASH_SLASH MODULO
                    DOT LESS_THAN_OR_EQUAL ALT_UNEQUAL LEFT_SHIFT
                    GREATER_THAN_OR_EQUAL RIGHT_SHIFT EQUAL UNEQUAL
                    COMMA COLON AT BITWISE_COMPLEMENT BITWISE_AND
                    BITWISE_OR BITWISE_XOR DOLLAR AND OR EOF], kinds
    assert_equal ['<', '>', '{', '}', '[', ']', '(', ')', '+', '-', '*', '/',
                  '**', '//', '%', '.', '<=', '<>', '<<', '>=', '>>', '==',
                  '!=', ',', ':', '@', '~', '&', '|', '^', '$', '&&', '||',
                  ''], texts
    keywords = 'true false null is in not and or'
    tokenizer = make_tokenizer keywords
    tokens = tokenizer.tokens
    kinds = tokens.map(&:kind)
    texts = tokens.map(&:text)
    assert_equal %i[TRUE FALSE NONE IS IN NOT AND OR EOF], kinds
    assert_equal ['true', 'false', 'null', 'is', 'in', 'not', 'and', 'or', ''], texts

    newlines = "\n \r \r\n"
    tokenizer = make_tokenizer newlines
    tokens = tokenizer.tokens
    kinds = tokens.map(&:kind)
    assert_equal %i[NEWLINE NEWLINE NEWLINE EOF], kinds

    assert_equal false, make_tokenizer('false').get_token.value
    assert_equal false, make_tokenizer('false').get_token.value
    assert_equal CFG::Config::NULL_VALUE, make_tokenizer('null').get_token.value
  end

  def test_data
    path = data_file_path 'testdata.txt'
    cases = load_data path
    expected = {
      'C25' => [
        make_token(:WORD, 'unicode', 'unicode', 1, 1, 1, 7),
        make_token(:ASSIGN, '=', nil, 1, 9, 1, 9),
        make_token(:STRING, "'Grüß Gott'", 'Grüß Gott', 1, 11, 1, 21),
        make_token(:NEWLINE, "\n", nil, 1, 22, 2, 0),
        make_token(:WORD, 'more_unicode', 'more_unicode', 2, 1, 2, 12),
        make_token(:COLON, ':', nil, 2, 13, 2, 13),
        make_token(:STRING, "'Øresund'", 'Øresund', 2, 15, 2, 23),
        make_token(:EOF, '', nil, 2, 24, 2, 24)
      ]
    }
    cases.each do |k, v|
      tokenizer = make_tokenizer v

      # require 'byebug'; byebug if k == 'C25'
      tokens = tokenizer.tokens
      assert_equal expected[k], tokens[0..expected[k].size - 1] if expected.key?(k)
    end
  end

  def test_locations
    path = data_file_path 'pos.forms.cfg.txt'
    expected = []
    f = File.open path, 'r:utf-8'
    f.each do |line|
      nums = line.rstrip.split(' ').map(&:to_i)
      assert nums.length == 4
      expected.push nums
    end
    f.close
    path = data_file_path 'forms.cfg'
    f = File.open path, 'r:utf-8'
    tokenizer = CFG::Config::Tokenizer.new f
    tokens = tokenizer.tokens
    f.close
    assert_equal tokens.length, expected.length
    tokens.each_with_index do |t, i|
      nums = expected[i]
      assert_equal t.start.line, nums[0]
      assert_equal t.start.column, nums[1]
      assert_equal t.end.line, nums[2]
      assert_equal t.end.column, nums[3]
    end
  end

  def test_bad_tokens
    bad_things = [
      # numbers

      ['9a', 'Invalid character in number', 1, 2],
      ['079', 'Invalid character in number', 1, 1],
      ['0xaBcz', 'Invalid character in number', 1, 6],
      ['0o79', 'Invalid character in number', 1, 4],
      ['.5z', 'Invalid character in number', 1, 3],
      ['0.5.7', 'Invalid character in number', 1, 4],
      [' 0.4e-z', 'Invalid character in number', 1, 7],
      [' 0.4e-8.3', 'Invalid character in number', 1, 8],
      [' 089z', 'Invalid character in number', 1, 5],
      ['0o89z', 'Invalid character in number', 1, 3],
      ['0X89g', 'Invalid character in number', 1, 5],
      ['10z', 'Invalid character in number', 1, 3],
      [' 0.4e-8Z', 'Invalid character in number: Z', 1, 8],
      ['123_', "Invalid '_' at end of number: 123_", 1, 4],
      ['1__23', "Invalid '_' in number: 1__", 1, 3],
      ['1_2__3', "Invalid '_' in number: 1_2__", 1, 5],
      [' 0.4e-8_', "Invalid '_' at end of number: 0.4e-8_", 1, 8],
      [' 0.4_e-8', "Invalid '_' at end of number: 0.4_", 1, 5],
      [' 0._4e-8', "Invalid '_' in number: 0._", 1, 4],
      ['\\ ', 'Unexpected character: \\', 1, 2],

      # strings

      ["'", 'Unterminated quoted string:', 1, 1],
      ['"', 'Unterminated quoted string:', 1, 1],
      ["'''", 'Unterminated quoted string:', 1, 1],
      ['  ;', 'Unexpected character: ', 1, 3],
      ['"abc', 'Unterminated quoted string: ', 1, 1],
      ["\"abc\\\ndef", 'Unterminated quoted string: ', 1, 1],
    ]

    bad_things.each do |bn|
      src, msg, line, col = bn
      tokenizer = make_tokenizer src
      begin
        t = tokenizer.get_token
        assert_nil t
      rescue CFG::Config::RecognizerError => e
        loc = e.location
        refute_nil e.message.index(msg)
        assert_equal line, loc.line
        assert_equal col, loc.column
      end
    end
  end

  def test_escapes
    good = [
      ["'\\a'", "\u0007"],
      ["'\\b'", "\b"],
      ["'\\f'", "\u000C"],
      ["'\\n'", "\n"],
      ["'\\r'", "\r"],
      ["'\\t'", "\t"],
      ["'\\v'", "\u000B"],
      ["'\\\\'", '\\'],
      ["'\\''", "'"],
      ["'\\\"'", '"'],
      ["'\\xAB'", "\u00AB"],
      ["'\\u2803'", "\u2803"],
      ["'\\u28A0abc\\u28A0'", "\u28a0abc\u28a0"],
      ["'\\u28A0abc'", "\u28a0abc"],
      ["'\\uE000'", "\ue000"],
      ["'\\U0010ffff'", "\u{10ffff}"]
    ]

    good.each do |acase|
      src, value = acase
      tokenizer = make_tokenizer src
      # require 'byebug'; byebug if src == "'\\U0010ffff'"
      t = tokenizer.get_token
      assert_equal value, t.value
    end

    bad = [
      "'\\z'",
      "'\\x'",
      "'\\xa'",
      "'\\xaz'",
      "'\\u'",
      "'\\u0'",
      "'\\u01'",
      "'\\u012'",
      "'\\u012z'",
      "'\\u012zA'",
      "'\\ud800'",
      "'\\udfff'",
      "'\\U00110000'"
    ]

    bad.each do |s|
      begin
        make_tokenizer(s).get_token
      rescue CFG::Config::RecognizerError => e
        refute_nil e.message.index 'Invalid escape sequence'
      end
    end
  end
end
