require 'bcrypt'
require 'redcarpet'
require 'sinatra'
require 'sinatra/reloader'
require 'sinatra/content_for'
require 'tilt/erubis'
require 'yaml'

TEXT_EXTENSIONS = %w(.md .txt .doc).freeze
IMAGE_EXTENSIONS = %w(.jpg .jpeg .gif .png).freeze
UPLOAD_EXTENSIONS = %w(.md .txt .pdf .jpg .jpeg .gif .png).freeze

configure do
  enable :sessions
  set :session_secret, 'secret'
  set :erb, escape_html: true
end

before do
  pattern = File.join(data_path, '*')
  @files = Dir.glob(pattern).map do |path|
    name = File.basename(path)
    name.start_with?(/[A-Z]/) ? name : name.capitalize
  end.sort
end

helpers do
  def read_message
    if session[:error]
      :error
    elsif session[:success]
      :success
    end
  end

  def split_name(file_name)
    file_name.split('.')
  end

  def text_extension?(file_name)
    TEXT_EXTENSIONS.include?(File.extname(file_name))
  end
end

def data_path
  if ENV['RACK_ENV'] == 'test'
    File.expand_path('../test/data', __FILE__)
  else
    File.expand_path('../data', __FILE__)
  end
end

def upload_path
  File.expand_path('../test', __FILE__) if ENV['RACK_ENV'] == 'test'
end

def credentials_path
  if ENV['RACK_ENV'] == 'test'
    File.expand_path('../test/users.yml', __FILE__)
  else
    File.expand_path('../users.yml', __FILE__)
  end
end

def load_user_credentials
  YAML.load_file(credentials_path)
end

def encrypt_password(password)
  BCrypt::Password.create(password)
end

def clean_yaml
  content = ''
  File.open(credentials_path) do |users|
    content = users.read.gsub(/\n-{3}/, '')
  end
  File.open(credentials_path, 'w') do |users|
    users.write(content)
  end
end

# append new user to credentials list
def write_user_credentials(username, password)
  File.open(credentials_path, 'a') do |users|
    users.write(Psych.dump("#{username}": encrypt_password(password)))
  end
  clean_yaml
end

def invalid_file_type?(possible_extensions, file_name)
  !possible_extensions.include?(File.extname(file_name).downcase)
end

def simplify_file_name!(name)
  file, extension = split_name(name)
  extension = extension.gsub(/[A-Z]/, 'a-z')
  file = file.split.map(&:capitalize).join.gsub(/['"]/, '').strip
  "#{file}.#{extension}"
end

def render_markdown(text)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(text)
end

def verify_signed_in
  return if session[:signed_in]
  session[:error] = 'You must be signed in to do that.'
  redirect '/'
end

def valid_credentials?(username, password)
  credentials = load_user_credentials
  if credentials.key?(username.to_sym)
    bcrypt_password = BCrypt::Password.new(credentials[username])
    bcrypt_password == password
  else
    false
  end
end

def determine_text_display(extension, content)
  case extension
  when '.txt', '.doc'
    headers['Content-Type'] = 'text/plain'
    content
  when '.md'
    headers['Content-Type'] = 'text/html'
    erb render_markdown(content)
  end
end

def load_file_content(path)
  content = File.read(path)
  extension = File.extname(path)
  if TEXT_EXTENSIONS.include?(extension)
    determine_text_display(extension, content)
  elsif IMAGE_EXTENSIONS.include?(extension)
    headers['Content-Type'] = 'image/jpg'
    content
  elsif extension == '.pdf'
    headers['Content-Type'] = 'application/pdf'
    content
  end
end

def create_document(name, content = '')
  File.open(File.join(data_path, name), 'w') do |file|
    file.write(content)
  end
end

def file_exists?(file_name)
  File.file?(File.join(data_path, file_name))
end

def file_too_large?(file_name)
  File.size(file_name) >= 1_500_000
end

def invalid_new_document?(doc_name)
  if doc_name.empty?
    'A name is required.'
  elsif invalid_file_type?(TEXT_EXTENSIONS, doc_name)
    'Please include a valid extension for your file (use ' \
    "#{TEXT_EXTENSIONS.join(', ')})."
  elsif file_exists?(simplify_file_name!(doc_name))
    'That file already exists. Please choose another name.'
  end
end

def invalid_rename?(new_name, extension)
  if new_name.empty?
    'A name is required.'
  elsif file_exists?("#{new_name}.#{extension}")
    'That file already exists. Please choose another name.'
  end
end

def invalid_upload?(file_details)
  if file_details.nil?
    'Please select a file to upload.'
  elsif invalid_file_type?(UPLOAD_EXTENSIONS, file_details[:filename])
    "Unsupported file type. Please only use #{UPLOAD_EXTENSIONS.join(', ')}."
  elsif file_exists?(file_details[:filename])
    'That file already exists.'
  elsif file_too_large?(file_details[:tempfile])
    'The file is too big. Please resize or try another file.'
  end
end

# load index
get '/' do
  erb :index
end

# display registration form
get '/users/register' do
  erb :register
end

# register new user
post '/users/register' do
  username = params[:new_username]
  password = params[:new_password]
  if username.empty? || password.empty?
    status 422
    session[:error] = 'Please enter a valid username and password.'
    erb :register
  elsif load_user_credentials.key?(username.to_sym)
    status 409
    session[:error] = 'That username already exists. Please choose another.'
    erb :register
  else
    write_user_credentials(username, password)
    session[:success] = "Account successfully registered. Welcome, " \
                        "#{username}! Please save your password for future " \
                        "refrerence: #{password}"
    session[:signed_in] = true
    session[:username] = username
    redirect '/'
  end
end

# display form to create new document
get '/new' do
  verify_signed_in
  erb :new_file, layout: :layout
end

# display sign in form
get '/users/signin' do
  erb :sign_in
end

# sign in
post '/users/signin' do
  username = params[:username].strip
  password = params[:password].strip
  if valid_credentials?(username.to_sym, password)
    session[:success] = 'Welcome!'
    session[:signed_in] = true
    session[:username] = username
    redirect '/'
  else
    session[:error] = 'Invalid Credentials'
    status 409
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

# display upload form
get '/upload' do
  verify_signed_in
  erb :upload
end

# upload file
post '/upload' do
  verify_signed_in
  file_details = params[:fileupload]
  session[:error] = invalid_upload?(file_details)
  if session[:error]
    status 422
    erb :upload
  else
    file_name = simplify_file_name!(file_details[:filename])
    file = file_details[:tempfile]
    FileUtils.mv(file, File.join(data_path, file_name))
    session[:success] = "#{file_name} was uploaded."
    redirect '/'
  end
end

# create new document
post '/create' do
  verify_signed_in
  doc_name = params[:file_name].strip
  session[:error] = invalid_new_document?(doc_name)
  if session[:error]
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

# rename document
post '/:file_name/rename' do
  verify_signed_in
  old_name = params[:file_name]
  extension = split_name(params[:file_name]).last
  new_name = params[:rename].strip
  session[:error] = invalid_rename?(new_name, extension)
  if session[:error]
    status 422
    erb :rename
  else
    new_name = simplify_file_name!("#{new_name}.#{extension}")
    File.rename(File.join(data_path, old_name), File.join(data_path, new_name))
    session[:success] = "#{old_name} was renamed to #{new_name}."
    redirect '/'
  end
end

# duplicate a document
post '/:file_name/duplicate' do
  verify_signed_in
  doc_name = params[:file_name]
  name, extension = split_name(doc_name)
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
  if env['HTTP_X_REQUESTED_WITH'] == 'XMLHttpRequest'
    File.delete(file_path)
    status 204
  else
    File.delete(file_path)
    session[:success] = "#{doc} has been deleted."
    redirect '/'
  end
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
