#
# Copyright (C) 2021 Vinay Sajip <vinay_sajip@yahoo.co.uk>
#
# See LICENSE file for usage rights.
#
require 'date'
require 'stringio'

require 'test_helper'

include CFG

def parse(src, rule = 'mapping_body')
  p = make_parser src
  assert p.respond_to? rule
  p.public_send rule
end

def make_token(kind, text, value, sline, scol, eline = nil, ecol = nil)
  spos = Location.new sline, scol
  eline = sline if eline.nil?
  ecol = scol + (text.length.positive? ? text.length - 1 : text.length) if ecol.nil?
  epos = Location.new eline, ecol
  result = Token.new kind, text, value
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
    refute_nil VERSION
  end
end

class LocationTest < Minitest::Test
  def test_location
    loc1 = Location.new
    assert loc1.line == 1
    assert loc1.column == 1
    loc1.next_line
    loc1.next_line
    assert loc1.line == 3
    assert loc1.column == 1
    loc2 = Location.new
    assert loc2.line == 1
    assert loc2.column == 1
    loc2.update loc1
    assert loc2.line == 3
    assert loc2.column == 1
    assert loc2.to_s == '(3, 1)'
    loc3 = Location.from loc1
    assert loc3.line == 3
    assert loc3.column == 1
  end
end

class TokenTest < Minitest::Test
  def test_token
    t = Token.new(:EOF, '')
    assert_equal 'Token(EOF, "", nil)', t.to_s
  end
end

class TokenizerTest < Minitest::Test
  def test_init
    t = Tokenizer.new(nil)
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
    assert_equal NULL_VALUE, make_tokenizer('null').get_token.value
  end

  def test_data
    path = data_file_path 'testdata.txt'
    cases = load_data path
    expected = {
      'C25' => [
        make_token(:WORD, 'unicode', 'unicode', 1, 1),
        make_token(:ASSIGN, '=', nil, 1, 9),
        make_token(:STRING, "'Grüß Gott'", 'Grüß Gott', 1, 11),
        make_token(:NEWLINE, "\n", nil, 1, 22, 2, 0),
        make_token(:WORD, 'more_unicode', 'more_unicode', 2, 1),
        make_token(:COLON, ':', nil, 2, 13),
        make_token(:STRING, "'Øresund'", 'Øresund', 2, 15),
        make_token(:EOF, '', nil, 2, 24)
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
    tokenizer = Tokenizer.new f
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
      e = assert_raises(RecognizerError) { tokenizer.get_token }
      loc = e.location
      refute_nil e.message.index(msg)
      assert_equal line, loc.line
      assert_equal col, loc.column
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
      rescue RecognizerError => e
        refute_nil e.message.index 'Invalid escape sequence'
      end
    end
  end
end

def word_token(word, sline, scol)
  make_token(:WORD, word, word, sline, scol)
end

class ParserTest < Minitest::Test
  def test_token_values
    p = make_parser 'a + 4'
    # require 'byebug'; byebug
    node = p.expr
    refute_nil node
    assert_equal :PLUS, node.kind
    t = node.lhs
    refute_nil t
    assert_equal :WORD, t.kind
    assert_equal 'a', t.value
    t = node.rhs
    refute_nil t
    assert_equal :INTEGER, t.kind
    assert_equal 4, t.value
  end

  def test_fragments
    node = parse 'foo', 'expr'
    assert_equal 'foo', node.value
    node = parse '0.5', 'expr'
    assert_equal :FLOAT, node.kind
    assert_equal 0.5, node.value
    node = parse "'foo' \"bar\"", 'expr'
    assert_equal :STRING, node.kind
    assert_equal 'foobar', node.value
    node = parse 'a.b', 'expr'
    assert_equal :DOT, node.kind
    assert_equal 'a', node.lhs.value
    assert_equal 'b', node.rhs.value
  end

  def test_unaries
    ops = ['+', '-', '~', 'not ', '@']

    ops.each do |op|
      s = "#{op}foo"
      kind = make_tokenizer(op).get_token.kind
      node = parse s, 'expr'
      refute_nil node
      assert_equal kind, node.kind
      assert_equal 'foo', node.operand.value
    end
  end

  def expressions(ops, rule, multiple = true)
    ops.each do |op|
      kind = make_tokenizer(op).get_token.kind
      src = "foo#{op}bar"
      node = parse src, rule
      refute_nil node
      assert_equal kind, node.kind
      assert_equal 'foo', node.lhs.value
      assert_equal 'bar', node.rhs.value
      next unless multiple

      100.times do
        op1 = ops.sample
        op2 = ops.sample
        k1 = make_tokenizer(op1).get_token.kind
        k2 = make_tokenizer(op2).get_token.kind
        src = "foo#{op1}bar#{op2}baz"
        node = parse src, rule
        refute_nil node
        assert_equal k2, node.kind
        assert_equal 'baz', node.rhs.value
        assert_equal k1, node.lhs.kind
        assert_equal 'foo', node.lhs.lhs.value
        assert_equal 'bar', node.lhs.rhs.value
      end
    end
  end

  def test_binaries
    expressions ['*', '/', '//', '%'], 'mul_expr'
    expressions ['+', '-'], 'add_expr'
    expressions ['<<', '>>'], 'shift_expr'
    expressions ['&'], 'bitand_expr'
    expressions ['^'], 'bitxor_expr'
    expressions ['|'], 'bitor_expr'
    expressions ['**'], 'power', false
    node = parse 'foo**bar**baz', 'power'

    assert_equal :POWER, node.kind
    assert_equal :WORD, node.lhs.kind
    assert_equal 'foo', node.lhs.value
    assert_equal :POWER, node.rhs.kind
    assert_equal 'bar', node.rhs.lhs.value
    assert_equal 'baz', node.rhs.rhs.value

    # require 'byebug'; byebug
    node = parse 'foo is not bar', 'comparison'
    refute_nil node
    assert_equal :IS_NOT, node.kind
    assert_equal 'foo', node.lhs.value
    assert_equal 'bar', node.rhs.value

    node = parse 'foo not in bar', 'comparison'
    refute_nil node
    assert_equal :NOT_IN, node.kind
    assert_equal 'foo', node.lhs.value
    assert_equal 'bar', node.rhs.value

    expressions ['<=', '<>', '<', '>=', '>', '==', '!=', ' in ', ' is '], 'comparison', false
    expressions [' and ', '&&'], 'and_expr'
    expressions [' or ', '||'], 'expr'
  end

  def test_atoms
    ['[1, 2, 3]', '[1, 2, 3,]'].each do |s|
      node = parse s, 'atom'

      refute_nil node
      node.elements.each_with_index do |t, i|
        assert_equal i + 1, t.value
      end
    end
  end

  def test_data
    path = data_file_path 'testdata.txt'
    cases = load_data path

    expected_messages = {
      'D01' => 'Unexpected type for key: INTEGER',
      'D02' => 'Unexpected type for key: LEFT_BRACKET',
      'D03' => 'Unexpected type for key: LEFT_CURLY'
    }

    cases.each do |k, v|
      p = make_parser v
      if k < 'D01'
        node = p.mapping_body
        refute_nil node
        assert p.at_end
      else
        begin
          p.mapping_body
        rescue RecognizerError => e
          assert_equal expected_messages[k], e.message if expected_messages.include? k
        end
      end
    end
  end

  def test_json
    path = data_file_path 'forms.conf'
    f = File.open path, 'r:utf-8'
    parser = Parser.new f
    node = parser.mapping
    refute_nil node
    keys = node.elements.map { |item| item[0].value }
    assert_equal %w[refs fieldsets forms modals pages], keys
  end

  def test_unexpected
    cases = [
      ['{foo', 'mapping', 'Expected key-value separator, found: EOF', 1, 5],
      ['   :', 'value', 'Unexpected when looking for value: COLON', 1, 4],
      ['   :', 'atom', 'Unexpected: COLON', 1, 4],
    ]
    cases.each do |item|
      src, rule, msg, line, col = item
      begin
        parse src, rule
      rescue RecognizerError => e
        assert_equal msg, e.message
        assert_equal line, e.location.line
        assert_equal col, e.location.column
      end
    end
  end

  def test_files
    path = data_file_path 'derived'
    Dir.new(path).children.each do |fn|
      fn = File.expand_path fn, path
      f = File.open fn, 'r:utf-8'
      p = Parser.new f
      node = p.container
      refute_nil node
      f.close
    end
  end

  def test_slices
    cases = [
      ['foo[start:stop:step]', [['start', 5], ['stop', 11], ['step', 16]]],
      ['foo[start:stop]', [['start', 5], ['stop', 11], nil]],
      ['foo[start:stop:]', [['start', 5], ['stop', 11], nil]],
      ['foo[start:]', [['start', 5], nil, nil]],
      ['foo[start::]', [['start', 5], nil, nil]],
      ['foo[:stop]', [nil, ['stop', 6], nil]],
      ['foo[:stop:]', [nil, ['stop', 6], nil]],
      ['foo[::step]', [nil, nil, ['step', 7]]],
      ['foo[::]', [nil, nil, nil]],
      ['foo[:]', [nil, nil, nil]],
      ['foo[start::step]', [['start', 5], nil, ['step', 12]]],
    ]

    cases.each do |item|
      src, params = item
      node = parse src, 'expr'
      refute_nil node
      lhs = word_token 'foo', 1, 1
      args = []
      params.each do |p|
        if p.nil?
          arg = nil
        else
          word, scol = p
          arg = word_token word, 1, scol
        end
        args.push arg
      end
      rhs = SliceNode.new(*args)
      expected = BinaryNode.new :COLON, lhs, rhs
      assert_equal expected, node
    end

    # non-slice case
    node = parse 'foo[start]', 'expr'
    refute_nil node
    lhs = word_token 'foo', 1, 1
    rhs = word_token 'start', 1, 5
    expected = BinaryNode.new :LEFT_BRACKET, lhs, rhs
    assert_equal expected, node

    # failure cases
    cases = [
      ['foo[start::step:]', 'Expected RIGHT_BRACKET but got COLON', 1, 16],
      ['foo[a, b:c:d]', 'expected 1 expression, found 2', 1, 5],
      ['foo[a:b, c:d]', 'expected 1 expression, found 2', 1, 7],
      ['foo[a:b:c,d, e]', 'expected 1 expression, found 3', 1, 9],
    ]
    cases.each do |item|
      src, msg, line, col = item
      begin
        parse src, 'expr'
      rescue RecognizerError => e
        refute_nil e.message.index msg
        assert_equal line, e.location.line
        assert_equal col, e.location.column
      end
    end
  end
end

class ConfigTest < Minitest::Test
  def test_files
    not_mappings = Set['data.cfg', 'incl_list.cfg', 'pages.cfg', 'routes.cfg']
    path = data_file_path 'derived'
    Dir.new(path).children.each do |fn|
      p = File.expand_path fn, path
      c = Config.new
      begin
        c.load_file p
      rescue ConfigError => e
        if not_mappings.include? fn
          assert_equal 'Root configuration must be a mapping', e.message
        elsif fn == 'dupes.cfg'
          refute_nil e.message.index 'Duplicate key '
        end
      end
    end
  end

  def test_bad_paths
    cases = [
      ['foo[1, 2]', 'Invalid index at (1, 5): expected 1 expression, found 2'],
      ['foo[1] bar', nil],
      ['foo.123', nil],
      ['foo.', 'Expected WORD but got EOF'],
      ['foo[]', 'Invalid index at (1, 5): expected 1 expression, found 0'],
      ['foo[1a]', 'Invalid character in number: a'],
      ['4', nil]
    ]
    cases.each do |src, msg|
      e = assert_raises(InvalidPathError) { parse_path src }
      assert_equal "Invalid path: #{src}", e.message
      assert_equal msg, e.cause.message unless e.cause.nil?
    end
  end

  def test_identifiers
    cases = [
      ['foo', true],
      ["\u0935\u092e\u0938", true],
      ["\u73b0\u4ee3\u6c49\u8bed\u5e38\u7528\u5b57\u8868", true],
      ['foo ', false],
      ['foo[', false],
      ['foo [', false],
      ['foo.', false],
      ['foo .', false],
      ["\u0935\u092e\u0938.", false],
      ["\u73b0\u4ee3\u6c49\u8bed\u5e38\u7528\u5b57\u8868.", false],
      ['9', false],
      ['9foo', false],
      ['hyphenated-key', false]
    ]

    cases.each_with_index do |item, i|
      str, it_is = item
      is_it = Config.identifier? str
      assert_equal it_is, is_it, "Failed at #{i} for #{str}"
    end
  end

  def test_path_iteration
    start = make_token :INTEGER, '1', 1, 1, 5
    stop = make_token :INTEGER, '2', 2, 1, 7
    cases = [
      [
        'foo[bar].baz.bozz[3].fizz ',
        [
          word_token('foo', 1, 1),
          [:LEFT_BRACKET, 'bar'],
          [:DOT, 'baz'],
          [:DOT, 'bozz'],
          [:LEFT_BRACKET, 3],
          [:DOT, 'fizz'],
        ]
      ],
      [
        'foo[1:2]',
        [
          word_token('foo', 1, 1),
          [:COLON, SliceNode.new(start, stop, nil)]
        ]
      ],
    ]
    cases.each do |src, expected|
      node = parse_path src
      parts = unpack_path(node)
      assert_equal expected, parts
    end
  end

  def make_offset(hrs, mins, secs = 0)
    ((hrs * 60 + mins) * 60 + secs) / 86_400.0
  end

  def test_main_config
    rd = data_file_path 'derived'
    fn = File.join rd, 'main.cfg'
    config = Config.new
    config.include_path.push data_file_path('base')
    config.load_file fn
    log_conf = config['logging']
    assert_instance_of Config, log_conf
    assert_equal %w[formatters handlers loggers root], log_conf.as_dict.keys.sort
    e = assert_raises(InvalidPathError) { log_conf['handlers.file/filename'] }
    refute_nil e.message.index 'Invalid path: handlers.file/filename'
    assert_equal 'bar', log_conf.get('foo', 'bar')
    assert_equal 'baz', log_conf.get('foo.bar', 'baz')
    assert_equal 'bozz', log_conf.get('handlers.debug.levl', 'bozz')
    assert_equal 'run/server.log', log_conf['handlers.file.filename']
    assert_equal 'run/server-debug.log', log_conf['handlers.debug.filename']
    assert_equal %w[file error debug], log_conf['root.handlers']
    assert_equal %w[file error], log_conf['root.handlers[:2]']
    assert_equal %w[file debug], log_conf['root.handlers[::2]']

    test = config['test']
    assert_instance_of Config, test
    assert_equal 1.0e-7, test['float']
    assert_equal 0.3, test['float2']
    assert_equal 3.0, test['float3']
    assert_equal 2, test['list[1]']
    assert_equal 'b', test['dict.a']
    dt = Date.new 2019, 3, 28
    assert_equal dt, test['date']
    dt = DateTime.new 2019, 3, 28, 23, 27, 4.314159, make_offset(5, 30)
    assert_equal dt, test['date_time']
    dt = DateTime.new 2019, 3, 28, 23, 27, 4.314159, -make_offset(5, 30)
    assert_equal dt, test['neg_offset_time']
    dt = DateTime.new 2019, 3, 28, 23, 27, 4.271828
    assert_equal dt, test['alt_date_time']
    dt = DateTime.new 2019, 3, 28, 23, 27, 4
    assert_equal dt, test['no_ms_time']
    assert_equal 3.3, test['computed']
    assert_equal 2.7, test['computed2']
    assert_in_epsilon 0.9, test['computed3'], 1e-7
    assert_equal 10.0, test['computed4']
    assert_instance_of Config, config['base']
    expected = %w[derived_foo derived_bar derived_baz test_foo test_bar test_baz base_foo base_bar base_baz]
    assert_equal expected, config['combined_list']
    expected = {
      'foo_key' => 'base_foo',
      'bar_key' => 'base_bar',
      'baz_key' => 'base_baz',
      'base_foo_key' => 'base_foo',
      'base_bar_key' => 'base_bar',
      'base_baz_key' => 'base_baz',
      'derived_foo_key' => 'derived_foo',
      'derived_bar_key' => 'derived_bar',
      'derived_baz_key' => 'derived_baz',
      'test_foo_key' => 'test_foo',
      'test_bar_key' => 'test_bar',
      'test_baz_key' => 'test_baz'
    }
    assert_equal expected, config['combined_map_1']
    expected = {
      'derived_foo_key' => 'derived_foo',
      'derived_bar_key' => 'derived_bar',
      'derived_baz_key' => 'derived_baz'
    }
    assert_equal expected, config['combined_map_2']
    assert_equal config['number_1'] & config['number_2'], config['number_3']
    assert_equal config['number_1'] ^ config['number_2'], config['number_4']
    cases = [
      ['logging[4]', 'string required, but found 4'],
      ['logging[:4]', 'slices can only operate on lists'],
      ['no_such_key', 'Not found in configuration: no_such_key']
    ]
    cases.each do |src, msg|
      e = assert_raises(ConfigError, BadIndexError) { config[src] }
      refute_nil e.message.index msg
    end
  end

  def test_example_config
    rd = data_file_path 'derived'
    fn = File.join rd, 'example.cfg'
    config = Config.new
    config.include_path.push data_file_path('base')
    config.load_file fn

    # strings
    assert_equal config['snowman_escaped'], config['snowman_unescaped']
    assert_equal "\u2603", config['snowman_escaped']
    assert_equal "\u{1f602}", config['face_with_tears_of_joy']
    assert_equal "\u{1f602}", config['unescaped_face_with_tears_of_joy']
    strings = config['strings']
    assert_equal "Oscar Fingal O'Flahertie Wills Wilde", strings[0]
    assert_equal 'size: 5"', strings[1]
    assert_equal "Triple quoted form\ncan span\n'multiple' lines", strings[2]
    assert_equal "with \"either\"\nkind of 'quote' embedded within", strings[3]

    # special strings
    assert_equal File::PATH_SEPARATOR, config['special_value_1']
    assert_equal ENV['HOME'], config['special_value_2']
    sv3 = config['special_value_3']
    assert_equal 2019, sv3.year
    assert_equal 3, sv3.month
    assert_equal 28, sv3.day
    assert_equal 23, sv3.hour
    assert_equal 27, sv3.minute
    assert_equal 4, sv3.second
    assert_equal 314_159_000, sv3.second_fraction * 1e9
    assert_equal make_offset(5, 30, 43), sv3.offset
    assert_equal 'bar', config['special_value_4']
    assert_in_epsilon DateTime.now.to_time.to_f, config['special_value_5'].to_time.to_f

    # integers
    assert_equal 123, config['decimal_integer']
    assert_equal 0x123, config['hexadecimal_integer']
    assert_equal 83, config['octal_integer']
    assert_equal 0b000100100011, config['binary_integer']

    # floats
    assert_equal 123.456, config['common_or_garden']
    assert_equal 0.123, config['leading_zero_not_needed']
    assert_equal 123.0, config['trailing_zero_not_needed']
    assert_equal 1.0e6, config['scientific_large']
    assert_equal 1.0e-7, config['scientific_small']
    assert_equal 3.14159, config['expression_1']

    # complex
    assert_equal Complex(3.0, 2.0), config['expression_2']
    assert_equal Complex(1.0, 3.0), config['list_value[4]']

    # boolean
    assert_equal true, config['boolean_value']
    assert_equal false, config['opposite_boolean_value']
    assert_equal false, config['computed_boolean_2']
    assert_equal true, config['computed_boolean_1']

    # list
    assert_equal %w[a b c], config['incl_list']

    # mapping
    expected = {
      'bar' => 'baz',
      'foo' => 'bar'
    }
    assert_equal expected, config['incl_mapping'].as_dict
    expected = {
      'baz' => 'bozz',
      'fizz' => 'buzz'
    }
    assert_equal expected, config['incl_mapping_body'].as_dict
  end

  def test_duplicates
    rd = data_file_path 'derived'
    fn = File.join rd, 'dupes.cfg'
    config = Config.new
    e = assert_raises(ConfigError) { config.load_file fn }
    refute_nil e.message.index 'Duplicate key '
    config.no_duplicates = false
    config.load_file fn
    assert_equal 'not again!', config['foo']
  end

  def test_context
    rd = data_file_path 'derived'
    fn = File.join rd, 'context.cfg'
    config = Config.new
    config.context = { 'bozz' => 'bozz-bozz' }
    config.load_file fn
    assert_equal 'bozz-bozz', config['baz']
    e = assert_raises(ConfigError) { config['bad'] }
    refute_nil e.message.index 'Unknown variable '
  end

  def test_expressions
    rd = data_file_path 'derived'
    fn = File.join rd, 'test.cfg'
    config = Config.new fn
    expected = { 'a' => 'b', 'c' => 'd' }
    assert_equal expected, config['dicts_added']
    expected = {
      'a' => { 'b' => 'c', 'w' => 'x' },
      'd' => { 'e' => 'f', 'y' => 'z' }
    }
    assert_equal expected, config['nested_dicts_added']
    expected = ['a', 1, 'b', 2]
    assert_equal expected, config['lists_added']
    assert_equal [1, 2], config['list[:2]']
    expected = { 'a' => 'b' }
    assert_equal expected, config['dicts_subtracted']
    expected = {}
    assert_equal expected, config['nested_dicts_subtracted']
    expected = {
      'a_list' => [1, 2, { 'a' => 3 }],
      'a_map' => { 'k1' => ['b', 'c', { 'd' => 'e' }] }
    }
    assert_equal expected, config['dict_with_nested_stuff']
    assert_equal [1, 2], config['dict_with_nested_stuff.a_list[:2]']
    assert_equal (-4), config['unary'] # rubocop:disable Style/RedundantParentheses
    assert_equal 'mno', config['abcdefghijkl']
    assert_equal 8, config['power']
    assert_equal 2.5, config['computed5']
    assert_equal 2, config['computed6']
    assert_equal Complex(3, 1), config['c3']
    assert_equal Complex(5, 5), config['c4']
    assert_equal 2, config['computed8']
    assert_equal 160, config['computed9']
    assert_equal 62, config['computed10']
    assert_equal 'b', config['dict.a']
    # second call should return the same
    assert_equal 'b', config['dict.a']

    # test interpolation

    assert_equal 'A-4 a test_foo true 10 1.0e-07 1 b [a, c, e, g]Z', config['interp']
    assert_equal '{a: b}', config['interp2']

    # test failure cases
    cases = [
      ['bad_include', '@ operand must be a string'],
      ['computed7', 'Not found in configuration: float4'],
      ['bad_interp', 'Unable to convert string ']
    ]
    cases.each do |src, msg|
      e = assert_raises(ConfigError) { config[src] }
      refute_nil e.message.index msg
    end
  end

  def test_forms
    rd = data_file_path 'derived'
    fn = File.join rd, 'forms.cfg'
    config = Config.new
    config.include_path.push data_file_path('base')
    config.load_file fn
    expected = config.get('modals.deletion.contents[0].id', NULL_VALUE)
    assert_equal expected, 'frm-deletion'
    cases = [
      [
        'refs.delivery_address_field',
        {
          'kind' => 'field',
          'type' => 'textarea',
          'name' => 'postal_address',
          'label' => 'Postal address',
          'label_i18n' => 'postal-address',
          'short_name' => 'address',
          'placeholder' => 'We need this for delivering to you',
          'ph_i18n' => 'your-postal-address',
          'message' => ' ',
          'required' => true,
          'attrs' => { 'minlength' => 10 },
          'grpclass' => 'col-md-6'
        },
      ],
      [
        'refs.delivery_instructions_field',
        {
          'kind' => 'field',
          'type' => 'textarea',
          'name' => 'delivery_instructions',
          'label' => 'Delivery Instructions',
          'short_name' => 'notes',
          'placeholder' => 'Any special delivery instructions?',
          'message' => ' ',
          'label_i18n' => 'delivery-instructions',
          'ph_i18n' => 'any-special-delivery-instructions',
          'grpclass' => 'col-md-6'
        }
      ],
      [
        'refs.verify_field',
        {
          'kind' => 'field',
          'type' => 'input',
          'name' => 'verification_code',
          'label' => 'Verification code',
          'label_i18n' => 'verification-code',
          'short_name' => 'verification code',
          'placeholder' => 'Your verification code (NOT a backup code)',
          'ph_i18n' => 'verification-not-backup-code',
          'attrs' => {
            'minlength' => 6,
            'maxlength' => 6,
            'autofocus' => true
          },
          'append' => {
            'label' => 'Verify',
            'type' => 'submit',
            'classes' => 'btn-primary'
          },
          'message' => ' ',
          'required' => true
        }
      ],
      [
        'refs.signup_password_field',
        {
          'kind' => 'field',
          'type' => 'password',
          'label' => 'Password',
          'label_i18n' => 'password',
          'message' => ' ',
          'name' => 'password',
          'ph_i18n' => 'password-wanted-on-site',
          'placeholder' => 'The password you want to use on this site',
          'required' => true,
          'toggle' => true
        }
      ],
      [
        'refs.signup_password_conf_field',
        {
          'kind' => 'field',
          'type' => 'password',
          'name' => 'password_conf',
          'label' => 'Password confirmation',
          'label_i18n' => 'password-confirmation',
          'placeholder' => 'The same password, again, to guard against mistyping',
          'ph_i18n' => 'same-password-again',
          'message' => ' ',
          'toggle' => true,
          'required' => true
        }
      ],
      [
        'fieldsets.signup_ident[0].contents[0]',
        {
          'kind' => 'field',
          'type' => 'input',
          'name' => 'display_name',
          'label' => 'Your name',
          'label_i18n' => 'your-name',
          'placeholder' => 'Your full name',
          'ph_i18n' => 'your-full-name',
          'message' => ' ',
          'data_source' => 'user.display_name',
          'required' => true,
          'attrs' => { 'autofocus' => true },
          'grpclass' => 'col-md-6'
        }
      ],
      [
        'fieldsets.signup_ident[0].contents[1]',
        {
          'kind' => 'field',
          'type' => 'input',
          'name' => 'familiar_name',
          'label' => 'Familiar name',
          'label_i18n' => 'familiar-name',
          'placeholder' => 'If not just the first word in your full name',
          'ph_i18n' => 'if-not-first-word',
          'data_source' => 'user.familiar_name',
          'message' => ' ',
          'grpclass' => 'col-md-6'
        }
      ],
      [
        'fieldsets.signup_ident[1].contents[0]',
        {
          'kind' => 'field',
          'type' => 'email',
          'name' => 'email',
          'label' => 'Email address (used to sign in)',
          'label_i18n' => 'email-address',
          'short_name' => 'email address',
          'placeholder' => 'Your email address',
          'ph_i18n' => 'your-email-address',
          'message' => ' ',
          'required' => true,
          'data_source' => 'user.email',
          'grpclass' => 'col-md-6'
        }
      ],
      [
        'fieldsets.signup_ident[1].contents[1]',
        {
          'kind' => 'field',
          'type' => 'input',
          'name' => 'mobile_phone',
          'label' => 'Phone number',
          'label_i18n' => 'phone-number',
          'short_name' => 'phone number',
          'placeholder' => 'Your phone number',
          'ph_i18n' => 'your-phone-number',
          'classes' => 'numeric',
          'message' => ' ',
          'prepend' => { 'icon' => 'phone' },
          'attrs' => { 'maxlength' => 10 },
          'required' => true,
          'data_source' => 'customer.mobile_phone',
          'grpclass' => 'col-md-6'
        }
      ]
    ]
    cases.each do |path, exp|
      assert_equal exp, config[path]
    end
  end

  def test_path_across_includes
    rd = data_file_path 'base'
    fn = File.join rd, 'main.cfg'
    config = Config.new fn
    assert_equal 'run/server.log', config['logging.appenders.file.filename']
    assert_equal true, config['logging.appenders.file.append']
    assert_equal 'run/server-errors.log', config['logging.appenders.error.filename']
    assert_equal false, config['logging.appenders.error.append']
    assert_equal 'https://freeotp.github.io/', config['redirects.freeotp.url']
    assert_equal false, config['redirects.freeotp.permanent']
  end

  def test_sources
    cases = [
      'foo[::2]',
      'foo[:]',
      'foo[:2]',
      'foo[2:]',
      'foo[::1]',
      'foo[::-1]',
      'foo[3]'
    ]
    cases.each do |src|
      node = parse_path src
      assert_equal src, to_source(node)
    end
  end

  def test_bad_conversions
    config = Config.new
    cases = [
      'foo'
    ]
    cases.each do |it|
      config.strict_conversions = true
      e = assert_raises(ConfigError) { config.convert_string it }
      refute_nil e.message.index "Unable to convert string #{it}"
      config.strict_conversions = false
      s = config.convert_string it
      assert s.equal? it
    end
  end

  def test_circular_references
    rd = data_file_path 'derived'
    fn = File.join rd, 'test.cfg'
    config = Config.new fn
    cases = [
      ['circ_list[1]', 'Circular reference: circ_list[1] (46, 5)'],
      ['circ_map.a', 'Circular reference: circ_map.a (53, 8), circ_map.b (51, 8), circ_map.c (52, 8)']
    ]
    cases.each do |path, msg|
      e = assert_raises(CircularReferenceError) { config[path] }
      assert_equal msg, e.message
    end
  end

  def test_caching
    rd = data_file_path 'derived'
    fn = File.join rd, 'test.cfg'
    config = Config.new fn
    config.cached = true
    v1 = config['time_now']
    sleep 0.05
    v2 = config['time_now']
    assert_equal v1, v2
    config.cached = false
    v3 = config['time_now']
    sleep 0.05
    v4 = config['time_now']
    refute_equal v3, v4
    refute_equal v3, v1
  end

  def test_slices_and_indices
    rd = data_file_path 'derived'
    fn = File.join rd, 'test.cfg'
    config = Config.new fn
    the_list = %w[a b c d e f g]

    # slices

    assert_equal the_list, config['test_list[:]']
    assert_equal the_list, config['test_list[::]']
    assert_equal the_list, config['test_list[:20]']
    assert_equal %w[a b c d], config['test_list[-20:4]']
    assert_equal the_list, config['test_list[-20:20]']
    assert_equal %w[c d e f g], config['test_list[2:]']
    assert_equal %w[e f g], config['test_list[-3:]']
    assert_equal %w[f e d], config['test_list[-2:2:-1]']
    assert_equal %w[g f e d c b a], config['test_list[::-1]']
    assert_equal %w[c e], config['test_list[2:-2:2]']
    assert_equal %w[a c e g], config['test_list[::2]']
    assert_equal %w[a d g], config['test_list[::3]']
    assert_equal %w[a g], config['test_list[::2][::3]']

    # indices

    the_list.each_with_index do |v, i|
      assert_equal v, config["test_list[#{i}]"]
    end

    # negative indices

    n = the_list.length
    n.downto 1 do |i|
      assert_equal the_list[n - i], config["test_list[-#{i}]"]
    end

    # invalid indices

    [n, n + 1, -(n + 1), -(n + 2)].each do |i|
      e = assert_raises(ConfigError) { config["test_list[#{i}]"] }
      refute_nil e.message.index 'index out of range: '
    end
  end

  def test_include_paths
    rd = data_file_path 'derived'
    p1 = File.join(rd, 'test.cfg')
    p2 = File.absolute_path p1
    [p1, p2].each { |fn|
      src = "test: @'#{fn}'"
      stream = StringIO.new src, 'r:utf-8'
      cfg = Config.new stream
      assert_equal 2, cfg['test.computed6']
    }
  end

  def test_nested_include_paths
    rd = data_file_path 'base'
    fn = File.absolute_path File.join(rd, 'top.cfg')
    cfg = Config.new
    cfg.include_path.push data_file_path('derived')
    cfg.include_path.push data_file_path('another')
    cfg.load_file fn
    assert_equal 42, cfg['level1.level2.final']
  end

  def test_recursive_configuration
    rd = data_file_path 'derived'
    fn = File.join rd, 'recurse.cfg'
    config = Config.new fn
    e = assert_raises(ConfigError) { config['recurse'] }
    assert_equal e.message, 'Configuration cannot include itself: recurse.cfg'
  end
end
