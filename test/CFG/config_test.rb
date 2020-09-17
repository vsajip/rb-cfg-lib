require 'stringio'

require 'test_helper'

def make_tokenizer(s)
  stream = StringIO.new s
  CFG::Config::Tokenizer.new stream
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
    tokenizer = make_tokenizer('')
    t = tokenizer.get_token
    assert_equal :EOF,  t.kind
    assert_equal :EOF,  tokenizer.get_token.kind

    tokenizer = make_tokenizer("# a comment\n")
    t = tokenizer.get_token
    assert_equal :NEWLINE,  t.kind
    assert_equal '# a comment',  t.text
    assert_equal :EOF,  tokenizer.get_token.kind

    tokenizer = make_tokenizer('foo')
    t = tokenizer.get_token
    assert_equal :WORD, t.kind
    assert_equal "foo", t.text
    assert_equal '(1, 1)', t.start.to_s
    assert_equal '(1, 3)', t.end.to_s
    assert_equal :EOF,  tokenizer.get_token.kind

    tokenizer = make_tokenizer("`foo`")
    t = tokenizer.get_token
    assert_equal :BACKTICK, t.kind
    assert_equal "`foo`", t.text
    assert_equal 'foo', t.value
    assert_equal '(1, 1)', t.start.to_s
    assert_equal '(1, 5)', t.end.to_s
    assert_equal :EOF,  tokenizer.get_token.kind

    tokenizer = make_tokenizer("'foo'")
    t = tokenizer.get_token
    assert_equal :STRING, t.kind
    assert_equal "'foo'", t.text
    assert_equal 'foo', t.value
    assert_equal '(1, 1)', t.start.to_s
    assert_equal '(1, 5)', t.end.to_s
    assert_equal :EOF,  tokenizer.get_token.kind

    tokenizer = make_tokenizer '2.71828'
    t = tokenizer.get_token
    assert_equal :FLOAT, t.kind
    assert_equal  '2.71828', t.text
    assert_equal 2.71828, t.value
    assert_equal '(1, 7)', t.end.to_s
    assert_equal :EOF,  tokenizer.get_token.kind

    tokenizer = make_tokenizer '.5'
    t = tokenizer.get_token
    assert_equal :FLOAT, t.kind
    assert_equal '.5', t.text
    assert_equal 0.5, t.value
    assert_equal '(1, 2)', t.end.to_s
    assert_equal :EOF,  tokenizer.get_token.kind

    tokenizer = make_tokenizer '-.5'
    t = tokenizer.get_token
    assert_equal :FLOAT, t.kind
    assert_equal '-.5', t.text
    assert_equal (-0.5), t.value
    assert_equal '(1, 3)', t.end.to_s
    assert_equal :EOF,  tokenizer.get_token.kind

    tokenizer = make_tokenizer '0x123aBc'
    t = tokenizer.get_token
    assert_equal :INTEGER, t.kind
    assert_equal "0x123aBc", t.text
    assert_equal 0x123abc, t.value
    assert_equal '(1, 8)', t.end.to_s
    assert_equal :EOF,  tokenizer.get_token.kind

    tokenizer = make_tokenizer '0o123'
    t = tokenizer.get_token
    assert_equal :INTEGER, t.kind
    assert_equal '0o123', t.text
    assert_equal 83, t.value
    assert_equal '(1, 5)', t.end.to_s
    assert_equal :EOF,  tokenizer.get_token.kind

    tokenizer = make_tokenizer '0123'
    t = tokenizer.get_token
    assert_equal :INTEGER, t.kind
    assert_equal '0123', t.text
    assert_equal 83, t.value
    assert_equal '(1, 4)', t.end.to_s
    assert_equal :EOF,  tokenizer.get_token.kind

    tokenizer = make_tokenizer '0b0001_0110_0111'
    t = tokenizer.get_token
    assert_equal :INTEGER, t.kind
    assert_equal '0b0001_0110_0111', t.text
    assert_equal 0x167, t.value
    assert_equal '(1, 16)', t.end.to_s
    assert_equal :EOF,  tokenizer.get_token.kind

    tokenizer = make_tokenizer '1e8'
    t = tokenizer.get_token
    assert_equal :FLOAT, t.kind
    assert_equal '1e8', t.text
    assert_equal 1e8, t.value
    assert_equal '(1, 3)', t.end.to_s
    assert_equal :EOF,  tokenizer.get_token.kind

    tokenizer = make_tokenizer '1e-8'
    t = tokenizer.get_token
    assert_equal :FLOAT, t.kind
    assert_equal '1e-8', t.text
    assert_equal 1e-8, t.value
    assert_equal '(1, 4)', t.end.to_s
    assert_equal :EOF,  tokenizer.get_token.kind

    tokenizer = make_tokenizer '-4'
    t = tokenizer.get_token
    assert_equal :INTEGER, t.kind
    assert_equal '-4', t.text
    assert_equal -4, t.value
    assert_equal '(1, 2)', t.end.to_s
    assert_equal :EOF,  tokenizer.get_token.kind

    tokenizer = make_tokenizer '-4e8'
    t = tokenizer.get_token
    assert_equal :FLOAT, t.kind
    assert_equal '-4e8', t.text
    assert_equal -4e8, t.value
    assert_equal '(1, 4)', t.end.to_s
    assert_equal :EOF,  tokenizer.get_token.kind
  end

end
