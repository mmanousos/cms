ENV['RACK_ENV'] = 'test'

require 'fileutils'
require 'minitest/autorun'
require 'minitest/pride'
require 'rack/test'

require_relative '../cms'

class CmsTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(data_path)
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end

  def create_document(name, content = "")
    File.open(File.join(data_path, name), "w") do |file|
      file.write(content)
    end
  end

  def test_index
    create_document("about.md")
    create_document("changes.txt")

    get '/'
    assert_equal(200, last_response.status)
    assert_equal('text/html;charset=utf-8', last_response['Content-Type'])
    assert_includes(last_response.body, 'about.md')
    assert_includes(last_response.body, 'changes.txt')
  end

  def test_document
    create_document("history.txt", "1993 - Yukihiro Matsumoto dreams up Ruby.\n1995 - Ruby 0.95 released.")

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

  def test_markdown
    create_document('about.md', "* natural to read\n* easy to write")

    get '/about.md'
    assert_equal(200, last_response.status)
    assert_equal "text/html", last_response["Content-Type"]
    assert_includes(last_response.body, "<li>natural to read</li>\n<li>easy to write</li>")
  end

  def test_edit
    create_document('about.md')

    get '/about.md/edit'
    assert_equal(200, last_response.status)
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes(last_response.body, "textarea")
    assert_includes(last_response.body, "form")
    assert_includes(last_response.body, "button")
  end

  def test_post_edit
    create_document('changes.txt', 'old content')

    post '/changes.txt', content: 'new content'
    assert_equal(302, last_response.status)

    get last_response['Location']
    assert_equal('text/html;charset=utf-8', last_response['Content-Type'])
    assert_includes(last_response.body, 'changes.txt has been updated.')

    get '/'
    assert_equal(200, last_response.status)
    refute_includes(last_response.body, 'changes.txt has been updated.')

    get '/changes.txt'
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, 'new content')
  end

  def test_new_doc_form
    get '/new'
    assert_equal(200, last_response.status)
    assert_equal('text/html;charset=utf-8', last_response['Content-Type'])
    assert_includes(last_response.body, "<form action='/create' method='post'>")
    assert_includes(last_response.body, "<input type='text' name='file_name'")
    assert_includes(last_response.body, "<button type='submit'>")
  end

  def test_post_new_doc
    post '/create', file_name: 'test.md'
    assert_equal(302, last_response.status)

    get last_response['Location']
    assert_includes(last_response.body, 'test.md was created.')

    get '/'
    assert_equal(200, last_response.status)
    refute_includes(last_response.body, 'test.md was created.')
  end

  def test_post_invalid_doc_name
    post '/create', file_name: 'test'
    assert_equal(422, last_response.status)
    assert_includes(last_response.body, 'Please include an extension')

    post '/create', file_name: '   '
    assert_equal(422, last_response.status)
    assert_includes(last_response.body, 'A name is required.')
  end

  def test_delete
    create_document('to_delete.md', '')
    post '/to_delete.md/delete'
    assert_equal(302, last_response.status)

    get last_response['Location']
    assert_equal('text/html;charset=utf-8', last_response['Content-Type'])
    assert_includes(last_response.body, 'to_delete.md has been deleted.')

    get '/'
    assert_equal(200, last_response.status)
    refute_includes(last_response.body, 'to_delete.md has been deleted.')
    refute_includes(last_response.body, 'to_delete.md')
  end

  def test_sign_in
    get '/users/signin'
    assert_equal(200, last_response.status)
    assert_equal('text/html;charset=utf-8', last_response['Content-Type'])
    assert_includes(last_response.body, "id='username'")
    assert_includes(last_response.body, "id='password'")
    assert_includes(last_response.body, 'name="sign_in">Sign In</button>')

    post '/users/signin', username: 'admin', password: 'password'

    assert_equal(302, last_response.status)

    get last_response['Location']
    assert_equal('text/html;charset=utf-8', last_response['Content-Type'])
    assert_includes(last_response.body, 'Welcome!')
    assert_includes(last_response.body, 'Signed in as')
    assert_includes(last_response.body, 'Sign Out')

    get '/'
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, 'Signed in as')
    refute_includes(last_response.body, 'Welcome!')
    assert_includes(last_response.body, 'Sign Out')
  end

  def test_failed_sign_in
    # incorrect sign in - provide no credentials
    post 'users/signin', username: '', password: ''
    assert_equal(422, last_response.status)
    assert_includes(last_response.body, 'Invalid Credentials')

    post 'users/signin', username: 'xxx', password: 'xxx'
    assert_equal(422, last_response.status)
    assert_includes(last_response.body, 'Invalid Credentials')
  end

  def test_sign_out
    post 'users/signout'

    assert_equal(302, last_response.status)
    get last_response['Location']
    assert_includes(last_response.body, 'You have been signed out.')
    assert_includes(last_response.body, 'Sign In')

    get '/'
    assert_equal(200, last_response.status)
    refute_includes(last_response.body, 'You have been signed out.')
  end
end
