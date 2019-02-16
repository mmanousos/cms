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

  def session
    last_request.env['rack.session']
  end

  def create_document(name, content = "")
    File.open(File.join(data_path, name), "w") do |file|
      file.write(content)
    end
  end

  def admin_session
    { "rack.session" => { username: "admin", signed_in: true } }
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
    assert_equal('bad_doc.erb does not exist.', session[:error])

    get last_response['Location']
    assert_equal('text/html;charset=utf-8', last_response['Content-Type'])

    get '/'
    refute_equal('bad_doc.erb does not exist.', session[:error])
  end

  def test_markdown
    create_document('about.md', "* natural to read\n* easy to write")

    get '/about.md'
    assert_equal(200, last_response.status)
    assert_equal "text/html", last_response["Content-Type"]
    assert_includes(last_response.body, "<li>natural to read</li>\n<li>easy to write</li>")
  end

  def test_view_edit
    create_document('about.md')

    get '/about.md/edit', {}, admin_session
    assert_equal(200, last_response.status)
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes(last_response.body, "textarea")
    assert_includes(last_response.body, "form")
    assert_includes(last_response.body, "button")
  end

  def test_view_edit_not_signed_in
    get '/about.md/edit'
    assert_equal(302, last_response.status)
    assert_equal('You must be signed in to do that.', session[:error])
  end

  def test_post_edit
    create_document('changes.txt', 'old content')

    post '/changes.txt', {content: 'new content'}, admin_session
    assert_equal(302, last_response.status)
    assert_equal('changes.txt has been updated.', session[:success])

    get last_response['Location']
    assert_equal('text/html;charset=utf-8', last_response['Content-Type'])

    get '/'
    assert_equal(200, last_response.status)
    refute_equal('changes.txt has been updated.', session[:success])

    get '/changes.txt'
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, 'new content')
  end

  def test_post_edit_not_signed_in
    create_document('changes.txt', 'old content')
    post '/changes.txt'
    assert_equal(302, last_response.status)
    assert_equal('You must be signed in to do that.', session[:error])
  end

  def test_new_doc_form
    get '/new', {}, admin_session
    assert_equal(200, last_response.status)
    assert_equal('text/html;charset=utf-8', last_response['Content-Type'])
    assert_includes(last_response.body, "<form action='/create' method='post'>")
    assert_includes(last_response.body, "<input type='text' name='file_name'")
    assert_includes(last_response.body, "<button id='create' type='submit'>")
  end

  def test_new_doc_form_not_signed_in
    get '/new'
    assert_equal(302, last_response.status)
    assert_equal('You must be signed in to do that.', session[:error])
  end

  def test_post_new_doc
    post '/create', {file_name: 'test.md'}, admin_session
    assert_equal(302, last_response.status)
    assert_equal('test.md was created.', session[:success])

    get '/'
    assert_equal(200, last_response.status)
    refute_equal('test.md was created.', session[:success] )
  end

  def test_post_new_doc_not_signed_in
    post '/create'
    assert_equal(302, last_response.status)
    assert_equal('You must be signed in to do that.', session[:error])
  end

  def test_post_invalid_doc_name
    post '/create', {file_name: 'test'}, admin_session
    assert_equal(422, last_response.status)
    assert_includes(last_response.body, 'Please include a valid extension')

    post '/create', {file_name: '   '}, admin_session
    assert_equal(422, last_response.status)
    assert_includes(last_response.body, 'A name is required.')
  end

  def test_post_new_doc_already_exists
    create_document('copy.txt')
    post '/create', {file_name: 'copy.txt'}, admin_session
    assert_equal(422, last_response.status)
    assert_includes(last_response.body, 'That file already exists.')
  end

  def test_post_rename
    create_document('copy.txt')
    post '/copy.txt/rename', {rename: 'copy1.txt'}, admin_session
    assert_equal('copy.txt was renamed to copy1.txt.', session[:success])
    assert_equal(302, last_response.status)

    get last_response['Location']
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, 'copy1.txt</a>')
    refute_includes(last_response.body, 'copy.txt</a>')
  end

  def test_post_rename_invalid_doc_name
    create_document('copy.txt')

    post '/copy.txt/rename', {rename: '   '}, admin_session
    assert_equal(422, last_response.status)
    assert_includes(last_response.body, 'A name is required.')
  end

  def test_post_rename_already_exists
    create_document('copy.txt')
    post '/copy.txt/rename', {rename: 'copy'}, admin_session
    assert_equal(422, last_response.status)
    assert_includes(last_response.body, 'That file already exists.')
  end

  def test_post_rename_not_signed_in
    post '/:file_name/rename'
    assert_equal(302, last_response.status)
    assert_equal('You must be signed in to do that.', session[:error])
  end

  def test_duplicate
    create_document('to_duplicate.md')
    post '/to_duplicate.md/duplicate', {}, admin_session
    assert_includes(session[:success], 'Duplication successful')
    assert_equal(302, last_response.status)

    get last_response['Location']
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, 'to_duplicate_copy.md')
  end

  def test_duplicate_not_signed_in
    create_document('to_duplicate.md')
    post '/to_duplicate.md/duplicate'
    assert_equal(302, last_response.status)
    assert_equal('You must be signed in to do that.', session[:error])
  end

  def test_delete
    create_document('to_delete.md', '')
    post '/to_delete.md/delete', {file_name: 'to_delete.md'}, admin_session
    assert_equal(302, last_response.status)
    assert_equal('to_delete.md has been deleted.', session[:success])

    get last_response['Location']
    assert_equal('text/html;charset=utf-8', last_response['Content-Type'])

    get '/'
    assert_equal(200, last_response.status)
    refute_equal('to_delete.md has been deleted.', session[:success])
    refute_includes(last_response.body, 'to_delete.md')
  end

  def test_delete_not_signed_in
    create_document('to_delete.md', '')
    post '/to_delete.md/delete'
    assert_equal(302, last_response.status)
    assert_equal('You must be signed in to do that.', session[:error])
  end

  def test_sign_in
    get '/users/signin'
    assert_equal(200, last_response.status)
    assert_equal('text/html;charset=utf-8', last_response['Content-Type'])
    assert_includes(last_response.body, "id='username'")
    assert_includes(last_response.body, "id='password'")
    assert_includes(last_response.body, "name='signin'>Sign In</button>")

    post '/users/signin', username: 'admin', password: 'secret'
    assert_equal(302, last_response.status)
    assert_equal('Welcome!', session[:success])

    get last_response['Location']
    assert_equal('text/html;charset=utf-8', last_response['Content-Type'])

    assert_includes(last_response.body, 'Signed in as')
    assert_includes(last_response.body, 'Sign Out')

    get '/'
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, 'Signed in as')
    refute_equal('Welcome!', session[:success])
    assert_includes(last_response.body, 'Sign Out')
  end

  def test_failed_sign_in
    post '/users/signin', username: '', password: ''
    assert_equal(422, last_response.status)
    assert_includes(last_response.body, 'Invalid Credentials')

    post '/users/signin', username: 'xxx', password: 'xxx'
    assert_equal(422, last_response.status)
    assert_includes(last_response.body, 'Invalid Credentials')
  end

  def test_sign_out
    get '/', {}, admin_session
    assert_includes(last_response.body, 'Signed in as admin')

    post '/users/signout'
    assert_equal(302, last_response.status)
    assert_equal('You have been signed out.', session[:success])

    get last_response['Location']
    assert_nil(session[:username])
    assert_includes(last_response.body, 'Sign In')

    get '/'
    assert_equal(200, last_response.status)
    refute_equal('You have been signed out.', session[:success])
    refute_includes(last_response.body, 'Signed in as')
  end

  def test_display_upload_form
    get '/upload', {}, admin_session
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, 'enctype="multipart/form-data"')
  end

  def test_display_upload_form_not_signed_in
    get '/upload'
    assert_equal('You must be signed in to do that.', session[:error])
    assert_equal(302, last_response.status)
  end

  def test_upload
    skip
    # image = File.expand_path('../', 'panda.gif')
    file = Rack::Test::UploadedFile.new('../panda.gif', "image/jpeg")

    post '/upload', {fileupload: file}, admin_session
    assert_equal('was uploaded.', session[:success])

    get ['Location']
    assert_includes(last_response.body, 'panda.gif') #filename
  end

  def test_upload_no_file
    post '/upload', {}, admin_session
    assert_equal(422, last_response.status)
    assert_includes(last_response.body, 'Please select a file to upload.')
  end

  def test_upload_not_signed_in
    post '/upload'
    assert_equal('You must be signed in to do that.', session[:error])
    assert_equal(302, last_response.status)
  end
end
