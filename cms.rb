require 'bcrypt'
require 'redcarpet'
require 'sinatra'
require 'sinatra/reloader'
require 'sinatra/content_for'
require 'tilt/erubis'
require 'yaml'

configure do
  enable :sessions
  set :session_secret, 'secret'
  set :erb, escape_html: true
end

helpers do
  # get flash message
  def read_message
    if session[:error]
      :error
    elsif session[:success]
      :success
    end
  end
end

def data_path
  if ENV['RACK_ENV'] == 'test'
    File.expand_path('../test/data', __FILE__)
  else
    File.expand_path('../data', __FILE__)
  end
end

def load_user_credentials
  credentials_path = if ENV['RACK_ENV'] == 'test'
                       File.expand_path('../test/users.yml', __FILE__)
                     else
                       File.expand_path('../users.yml', __FILE__)
                     end
  YAML.load_file(credentials_path)
end

get '/' do
  pattern = File.join(data_path, '*')
  @files = Dir.glob(pattern).map do |path|
    File.basename(path)
  end
  erb :index
end

def render_markdown(text)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(text)
end

def load_file_content(path)
  content = File.read(path)
  if File.extname(path) == '.txt'
    headers['Content-Type'] = 'text/plain'
    content
  elsif File.extname(path) == '.md' || File.extname(path) == '.doc'
    headers['Content-Type'] = 'text/html'
    erb render_markdown(content)
  end
end

def signed_in?
  session[:signed_in]
end

def verify_signed_in
  return if signed_in?
  session[:error] = 'You must be signed in to do that.'
  redirect '/'
end

# display form to create new document
get '/new' do
  verify_signed_in
  erb :new_file, layout: :layout
end

def create_document(name, content = '')
  File.open(File.join(data_path, name), 'w') do |file|
    file.write(content)
  end
end

TEXT_EXTENSIONS = %w(.md .txt .doc).freeze
IMAGE_EXTENSIONS = %w(.jpg .jpeg .svg .gif .png).freeze
OTHER_EXTENSIONS = %w(.pdf).freeze

# display sign in form
get '/users/signin' do
  erb :sign_in
end

def valid_credentials?(username, password)
  credentials = load_user_credentials
  if credentials.key?(username)
    bcrypt_password = BCrypt::Password.new(credentials[username])
    bcrypt_password == password
  else
    false
  end
end

# sign in
post '/users/signin' do
  username = params[:username].strip
  password = params[:password].strip
  if valid_credentials?(username, password)
    session[:success] = 'Welcome!'
    session[:signed_in] = true
    session[:username] = username
    redirect '/'
  else
    session[:error] = 'Invalid Credentials'
    status 422
    erb :sign_in
  end
end

# sign out
post '/users/signout' do
  session[:signed_in] = false
  session.delete(:username)
  session[:success] = 'You have been signed out.'
  redirect '/'
end

def valid_text_extension?(name)
  TEXT_EXTENSIONS.include?(File.extname(name))
end

def simplify_file_name(name)
  name.downcase.tr(' ', '').strip
end

# validate and create new document
post '/create' do
  verify_signed_in
  doc_name = simplify_file_name(params[:file_name])
  if doc_name.empty?
    session[:error] = 'A name is required.'
    status 422
    erb :new_file
  elsif !valid_text_extension?(doc_name)
    session[:error] = 'Please include a valid extension for your file ' \
                      "(use #{TEXT_EXTENSIONS.join(', ')})."
    status 422
    erb :new_file
  elsif File.file?(File.join(data_path, doc_name))
    session[:error] = 'That file already exists. Please choose another name.'
    status 422
    erb :new_file
  else
    create_document(doc_name)
    session[:success] = "#{doc_name} was created."
    redirect '/'
  end
end

# display rename form
get '/:file_name/rename' do
  verify_signed_in
  erb :rename
end

# validate new name and rename document
post '/:file_name/rename' do
  verify_signed_in
  old_name = params[:file_name]
  new_name = simplify_file_name(params[:rename])
  if new_name.empty?
    session[:error] = 'A name is required.'
    status 422
    erb :rename
  elsif !valid_text_extension?(new_name)
    session[:error] = 'Please include a valid extension for your file ' \
                      "(use #{TEXT_EXTENSIONS.join(', ')})."
    status 422
    erb :rename
  elsif File.file?(File.join(data_path, new_name))
    session[:error] = 'That file already exists. Please choose another name.'
    status 422
    erb :rename
  else
    File.rename(File.join(data_path, old_name), File.join(data_path, new_name))
    session[:success] = "#{old_name} was renamed to #{new_name}."
    redirect '/'
  end
end

# duplicate a document
post '/:file_name/duplicate' do
  verify_signed_in
  doc_name = params[:file_name]
  name, extension = doc_name.split('.')
  content = File.read(File.join(data_path, doc_name))
  duplicate_name = name + '_copy.' + extension
  create_document(duplicate_name, content)
  session[:success] = "Duplication successful: #{duplicate_name} created."
  redirect '/'
end

# delete a document
post '/:file_name/delete' do
  verify_signed_in
  doc = params[:file_name]
  file_path = File.join(data_path, doc)
  File.delete(file_path)
  session[:success] = "#{doc} has been deleted."
  redirect '/'
end

# display document
get '/:file_name' do
  doc = params[:file_name]
  file_path = File.join(data_path, doc)
  if File.file?(file_path)
    @document = load_file_content(file_path)
  else
    session[:error] = "#{doc} does not exist."
    redirect '/'
  end
end

# display edit form
get '/:file_name/edit' do
  verify_signed_in
  @doc = params[:file_name]
  file_path = File.join(data_path, @doc)
  @document = File.read(file_path)
  erb :edit
end

# submit edits to file
post '/:file_name' do
  verify_signed_in
  doc = params[:file_name]
  file_path = File.join(data_path, doc)
  File.write(file_path, params[:content])
  session[:success] = "#{doc} has been updated."
  redirect '/'
end
