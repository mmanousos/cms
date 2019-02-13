require 'redcarpet'
require 'sinatra'
require 'sinatra/reloader'
require 'sinatra/content_for'
require 'tilt/erubis'

configure do
  enable :sessions
  set :session_secret, 'secret'
  set :erb, :escape_html => true
end

helpers do
  # get flash message
  def get_message
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
  case File.extname(path)
  when '.txt'
    headers['Content-Type'] = 'text/plain'
    content
  when '.md'
    headers['Content-Type'] = 'text/html'
    erb render_markdown(content)
  end
end

def signed_in?
  session[:signed_in]
end

def verify_signed_in
  unless signed_in?
    session[:error] = 'You must be signed in to do that.'
    redirect '/'
  end
end

# display form to create new document
get '/new' do
  verify_signed_in
  erb :new_file, layout: :layout
end

def create_document(name, content = "")
  File.open(File.join(data_path, name), "w") do |file|
    file.write(content)
  end
end

def valid_extension?(name)
  extension = File.extname(name)
  extension == '.md' || extension == '.txt'
end

# display sign in form
get '/users/signin' do
  erb :sign_in
end

# sign in
post '/users/signin' do
  username = params[:username].strip
  password = params[:password].strip
  if username.downcase == 'admin' && password.downcase == 'secret'
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

# validate and create new document
post '/create' do
  verify_signed_in
  doc_name = params[:file_name].strip
  if doc_name.empty?
    session[:error] = 'A name is required.'
    status 422
    erb :new_file
  elsif !valid_extension?(doc_name)
    session[:error] = 'Please include an extension for your file (use ".md" or ".txt").'
    status 422
    erb :new_file
  else
    create_document(doc_name)
    session[:success] = "#{doc_name} was created."
    redirect '/'
  end
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
