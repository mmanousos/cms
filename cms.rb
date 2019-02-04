require 'sinatra'
require 'sinatra/reloader'
require 'sinatra/content_for'
require 'tilt/erubis'

configure do
  enable :sessions
  set :session_secret, 'secret'
  set :erb, :escape_html => true
end

before do
  @root = File.expand_path("..", __FILE__)
  @files = Dir.glob(@root + "/data/*").map do |path|
    File.basename(path)
  end
end

get "/" do
  erb :index
end

# display document
get '/:file_name' do
  file_path = @root + '/data/' + params[:file_name]
  headers['Content-Type'] = 'text/plain'
  @doc = File.read(file_path)
end
