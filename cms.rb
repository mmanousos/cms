require 'bcrypt'
require 'redcarpet'
require 'sinatra'
require 'sinatra/reloader'
require 'sinatra/content_for'
require 'tilt/erubis'
require 'yaml'

include FileUtils

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

def load_user_credentials
  credentials_path = if ENV['RACK_ENV'] == 'test'
                       File.expand_path('../test/users.yml', __FILE__)
                     else
                       File.expand_path('../users.yml', __FILE__)
                     end
  YAML.load_file(credentials_path)
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
  if credentials.key?(username)
    bcrypt_password = BCrypt::Password.new(credentials[username])
    bcrypt_password == password
  else
    false
  end
end

# rubocop:disable Metrics/AbcSize
# rubocop:disable Metrics/MethodLength
def load_file_content(path)
  content = File.read(path)
  extension = File.extname(path)
  if extension == '.txt' || extension == '.doc'
    headers['Content-Type'] = 'text/plain'
    content
  elsif extension == '.md'
    headers['Content-Type'] = 'text/html'
    erb render_markdown(content)
  elsif IMAGE_EXTENSIONS.include?(extension)
    headers['Content-Type'] = 'image/jpg'
    content
  elsif extension == '.pdf'
    headers['Content-Type'] = 'application/pdf'
    content
  end
end
# rubocop:enable Metrics/AbcSize
# rubocop:enable Metrics/MethodLength

def create_document(name, content = '')
  File.open(File.join(data_path, name), 'w') do |file|
    file.write(content)
  end
end

def file_exists?(file_name)
  File.file?(File.join(data_path, file_name))
end

def file_too_large?(file_name)
  File.size(file_name) >= 1500000
end

# load index
get '/' do
  erb :index
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

# display upload form
get '/upload' do
  verify_signed_in
  erb :upload
end

# upload file
post '/upload' do
  verify_signed_in
  file_details = params[:fileupload]
  if file_details.nil?
    status 422
    session[:error] = 'Please select a file to upload.'
    erb :upload
  elsif invalid_file_type?(UPLOAD_EXTENSIONS, file_details[:filename])
    status 415
    session[:error] = 'That file type is unsupported. Please use only ' \
                      "#{UPLOAD_EXTENSIONS.join(', ')}."
    erb :upload
  elsif file_exists?(file_details[:filename])
    session[:error] = 'That file already exists.'
    status 422
    erb :upload
  elsif file_too_large?(file_details[:tempfile])
    session[:error] = 'The file is too big. Please resize or try another file.'
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

# validate and create new document
post '/create' do
  verify_signed_in
  doc_name = params[:file_name].strip
  if doc_name.empty?
    session[:error] = 'A name is required.'
    status 422
    erb :new_file
  elsif invalid_file_type?(TEXT_EXTENSIONS, doc_name)
    session[:error] = 'Please include a valid extension for your file ' \
                      "(use #{TEXT_EXTENSIONS.join(', ')})."
    status 422
    erb :new_file
  elsif file_exists?(simplify_file_name!(doc_name))
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
  extension = split_name(params[:file_name]).last
  new_name = params[:rename].strip
  if new_name.empty?
    session[:error] = 'A name is required.'
    status 422
    erb :rename
  elsif file_exists?("#{new_name}.#{extension}")
    session[:error] = 'That file already exists. Please choose another name.'
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
