ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'minitest/pride'
require 'rack/test'

require_relative '../cms'

class CmsTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def test_index
    get '/'
    assert_equal(200, last_response.status)
    assert_equal('text/html;charset=utf-8', last_response['Content-Type'])
    assert_includes(last_response.body, 'history.txt')
    assert_includes(last_response.body, 'about.txt')
    assert_includes(last_response.body, 'changes.txt')
  end

  def test_document
    get '/history.txt'
    assert_equal(200, last_response.status)
    assert_equal "text/plain", last_response["Content-Type"]
    assert_includes(last_response.body, 'Yukihiro Matsumoto')
  end

  def test_document_not_found
    get '/bad_doc.erb'
    assert_equal(302, last_response.status)

    get last_response['Location']
    assert_equal('text/html;charset=utf-8', last_response['Content-Type'])
    assert_includes(last_response.body, 'bad_doc.erb does not exist.')

    get '/'
    refute_includes(last_response.body, 'bad_doc.erb does not exist.')
  end
end
