require 'sinatra'
require 'sinatra/reloader' if development?
require 'tilt/erubis'
require 'yaml'
require 'fileutils'
require 'bcrypt'

configure do
  enable :sessions
  set :session_secret, 'secret'
  set :erb, escape_html: true
end

def credentials_path
  if ENV['RACK_ENV'] == 'test'
    File.expand_path('../test/users.yml', __FILE__)
  else
    File.expand_path('../users.yml', __FILE__)
  end
end

def load_credentials
  YAML.load_file(credentials_path)
end

def save_credentials(credentials)
  File.write(credentials_path, credentials.to_yaml)
end

def valid_credentials?(user, pass)
  credentials = load_credentials

  if credentials.key?(user)
    bcrypt_pass = BCrypt::Password.new(credentials[user])
    bcrypt_pass == pass
  else
    false
  end
end

def active_session?
  session[:user] != nil
end

def require_sign_in
  return if active_session?
  session[:message] = 'Please sign in.'
  redirect '/signin'
end

def valid_password?(pass1, pass2)
  return false if pass1 != pass2
  return false if pass1.size < 4
  return false if pass1.size > 10
end

def valid_username?(user)
  return false if user =~ /[^A-Za-z0-9]/
  return false if user.size < 4
  return false if user.size > 10
end

def signup_error(params)
  if valid_password?(params[:pass], params[:pass2]) == false
    'Invalid password.'
  elsif valid_username?(params[:user]) == false
    'Invalid username.'
  end
end

def contacts_path
  if ENV['RACK_ENV'] == 'test'
    File.expand_path("../test/data/#{session[:user]}", __FILE__)
  else
    File.expand_path("../data/#{session[:user]}", __FILE__)
  end
end

def load_contacts
  YAML.load_file(contacts_path + '/contacts.yml')
end

def save_contacts(contacts)
  File.write(contacts_path + '/contacts.yml', contacts.to_yaml)
end

def setup_contacts
  new_contacts unless contacts_exist?
  load_contacts
end

def contacts_exist?
  File.file?(contacts_path + '/contacts.yml')
end

def new_contacts
  FileUtils.mkdir_p(contacts_path)
  File.write(contacts_path + '/contacts.yml', {}.to_yaml)
end

def valid_name?(name)
  name == name.gsub(/[^A-Za-z]/, '') &&
    name.length < 30 &&
    name.length > 1
end

def valid_email?(email)
  return false unless email =~ /.{1,100}\@.{1,100}\.\w{2,3}$/
end

def valid_phone?(phone)
  return false unless phone =~ /^\d{3}\-\d{3}\-\d{4}$/
end

def contact_error(params)
  if valid_name?(params[:first]) == false
    'Invalid first name (check for length or invalid characters).'
  elsif valid_name?(params[:last]) == false
    'Invalid last name (check for length or invalid characters).'
  elsif valid_email?(params[:email]) == false
    'Invalid email address.'
  elsif valid_phone?(params[:phone]) == false
    'Invalid phone number (format must be 555-555-5555).'
  end
end

get '/' do
  require_sign_in

  @contacts = setup_contacts.sort_by { |_, v| v[:first] }

  erb :main
end

get '/signin' do
  erb :signin
end

post '/signin' do
  if valid_credentials?(params[:user], params[:pass])
    session[:user] = params[:user]
    session[:message] = 'Login successful. Enjoy your contacts.'
    redirect '/'
  else
    session[:message] = 'Invalid username and/or password'
    status 422
    erb :signin
  end
end

get '/signout' do
  session[:user] = nil
  session[:message] = 'Successfully logged out.'
  redirect '/signin'
end

get '/signup' do
  erb :signup
end

def bcrypt_pass(pass)
  BCrypt::Password.create(pass).to_s
end

post '/signup' do
  error = signup_error(params)

  if error
    session[:message] = error
    status 422
    erb :signup
  else
    credentials = load_credentials
    credentials[params[:user]] = bcrypt_pass(params[:pass])
    save_credentials(credentials)
    session[:message] = 'Account successfully created.'
    redirect '/signin'
  end
end

get '/add' do
  require_sign_in

  erb :add
end

post '/add' do
  require_sign_in

  error = contact_error(params)

  if error
    session[:message] = error
    status 422
    erb :add
  else
    contacts = setup_contacts

    first = params[:first].capitalize
    last = params[:last].capitalize
    email = params[:email]
    phone = params[:phone]
    id = contacts.size + 1

    contacts[id] = {
      first: first,
      last: last,
      email: email,
      phone: phone
    }

    save_contacts(contacts)

    session[:message] = 'Contact saved.'

    redirect '/'
  end
end

get '/details/:name' do
  require_sign_in

  contacts = setup_contacts
  @id = params[:name].to_i
  @first = contacts[@id][:first]
  @last = contacts[@id][:last]
  @email = contacts[@id][:email]
  @phone = contacts[@id][:phone]

  erb :details
end

get '/details/:name/edit' do
  require_sign_in

  contacts = setup_contacts
  @id = params[:name].to_i
  @first = contacts[@id][:first]
  @last = contacts[@id][:last]
  @email = contacts[@id][:email]
  @phone = contacts[@id][:phone]

  erb :edit
end

post '/details/:name/edit' do
  require_sign_in

  error = contact_error(params)

  @first = params[:first]
  @last = params[:last]
  @email = params[:email]
  @phone = params[:phone]
  @id = params[:name].to_i

  if error
    session[:message] = error
    status 422
    erb :edit
  else
    contacts = setup_contacts

    contacts[@id] = {
      first: @first.capitalize,
      last: @last.capitalize,
      email: @email,
      phone: @phone
    }

    save_contacts(contacts)

    session[:message] = 'Contact edits saved.'

    redirect "/details/#{params[:name]}"
  end
end

post '/details/:name/delete' do
  require_sign_in
  id = params[:name].to_i

  contacts = setup_contacts
  contacts.delete(id)
  save_contacts(contacts)

  session[:message] = 'Contact deleted.'

  redirect '/'
end
