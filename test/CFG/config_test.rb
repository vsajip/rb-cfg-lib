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
    assert t.to_s == 'Token(EOF, "", nil)'
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
    # refute_nil t
    # assert t.kind, :EOF
  end

end
