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
  @doc = params[:file_name]
  file_path = File.join(data_path, @doc)
  @document = File.read(file_path)
  erb :edit
end

# submit changes to file
post '/:file_name' do
  doc = params[:file_name]
  file_path = File.join(data_path, doc)
  File.write(file_path, params[:content])
  session[:success] = "#{doc} has been updated."
  redirect '/'
end

get '/index/new_file' do
  erb :new_file, layout: :layout
end

post '/:title' do
  doc_name = params[:title].strip
  if doc_name.empty?
    session[:error] = 'A name is required.'
    erb :new_file
  else
    # create new document in data folder
    File.new("/data/#{doc_name}")
    session[:success] = "#{doc_name} was created."
    redirect '/'
  end
end
