require 'data_mapper'
require 'sinatra'
require 'securerandom'
require 'date'
require 'time'
require 'digest/md5'
require 'resque'
 require 'dm-validations'

set :environment, :production
set :erb, :layout => false
set :sessions, true
Resque.redis = 'localhost:6379'

Dir[File.dirname(__FILE__) + '/workers/*.rb'].each {|file| require file }
DataMapper::Logger.new($stdout, :debug)
DataMapper.setup(:default, 'postgres://casuser:123456@10.1.0.195:5433/casauth2')

class User
	include DataMapper::Resource

	#attr_accessor :password, :password_confirmation

	property :id, Serial
	property :email, String,     :required => true, :unique => true
	
	property :created_at, DateTime 
	property :status, Integer	
	property :password, Text
	#property :password_hash,  Text  
   # property :password_salt,  Text    
   # validates_presence_of         :password
   # validates_confirmation_of     :password
   # validates_length_of           :password, :min => 6

    belongs_to :role	
    has 1, :profile
    has n, :activations
end
class Activation
	include DataMapper::Resource
	property :id, Serial
	property :token, String
	property :created_at, DateTime	
	property :description, Text
	property :status, Integer

	belongs_to :user 
end
class Profile
	include DataMapper::Resource
	property :id, Serial
	belongs_to :user
end
class Role
	include DataMapper::Resource
	property :id, Serial
	property :name, String	
	property :description, Text

	has n, :users
	has n, :services, :through => Resource
end

class Service
	include DataMapper::Resource
	property :id, Serial
	property :name, String
	property :url, String
	property :description, Text

	has n, :roles, :through => Resource	
end
DataMapper.finalize
DataMapper::Model.raise_on_save_failure = true 
#DataMapper.auto_migrate!


# profile view
get "/" do
	#@message = {:msg => 'Please register or login'}	 if session[:user] == nil
	erb :index
end

# update profile or reactivate
post "/" do
	if session[:user]
		email = params[:user][:email].gsub(/\s+/, "")
		password = params[:user][:password].gsub(/\s+/, "")
		password2 = params[:user][:password2].gsub(/\s+/, "")
		if password == password2
			if user = User.first(:email => session[:user]) then
				user.email = email
				user.password = Digest::MD5.hexdigest(password)
				if user.save
					@message = {:msg => 'Update profile successfully'}
					redirect '/'
				else
					user.errors.each do |e|
						puts e
					end
					@message = {:msg => 'Error saving user'}
					redirect '/'
				end
			end
		else
			@message = {:msg => 'Passwords are not the same'}
			redirect '/'
		end
	else
		@message = {:msg => 'Please login'}
		redirect '/'
	end
end

#reactivate account after expire
post "/reactivate" do
	if session[:user]	
		if current_user.status == 0 then
			if current_user.activations
				current_user.activations.each do |ac|
					ac.status = 1	if ac		
				end
			end
			register_confirm = Activation.new({:token => SecureRandom.hex, :created_at => Time.now, 
  	:description => 'Register confirmation', :status => 0})
			current_user.activations << register_confirm
			if current_user.save and register_confirm.save
				@message = {:msg => 'An email has been sent to #{email}'}
  				#sendmail(user.email, register_confirm.token, :registermail)
  				Resque.enqueue(SendEmail, current_user.email, register_confirm.token, 'register')
  				redirect '/'
			else
				@message = {:msg => 'Error reactivate'}
				redirect '/'
			end
		end
	else
		@message = {:msg => 'Please login'}
		redirect '/'
	end
end

get "/signup" do
	if session[:user]
  		redirect "/"
  	else 
  		erb :signup
  	end
end
post "/signup" do
  email = params[:user][:email].gsub(/\s+/, "")
  password = params[:user][:password] 
  password2 = params[:user][:password2] 
  puts "email #{email}, password #{Digest::MD5.hexdigest(password)}"
  if email.empty? or password.empty? or password2.empty?
  	@message = {:msg => 'Email or password cannot be blank'}
  	redirect '/signup'
  end
  if user = User.first(:email => email)
  	@message = {:msg => 'Exist email'}
  	redirect '/signup?email=#{params[:user][:email]}'
  end
  if params[:user][:password] != params[:user][:password2] 
  	@message = {:msg => 'Passwords are not the same'}
  	redirect '/signup?email=#{params[:user][:email]}'
  end
  pass_hash = Digest::MD5.hexdigest(password)
 
  role = Role.first_or_create(:name => 'Guest')
  user = User.new(:email => email, :password => pass_hash, :status => 0,  :created_at => Time.now)
  user.role = role
  register_confirm = Activation.new(:token => SecureRandom.hex, :created_at => Time.now, :description => 'Register confirmation', :status => 0)
  puts "user created: #{user.email}"
  register_confirm.user = user
  
  if user.save and register_confirm.save
  	@message = {:msg => 'An email has been sent to #{email}'}
  	Resque.enqueue(SendEmail, email, register_confirm.token, 'register')
  	#sendmail(user.email, register_confirm.token, :registermail)
    #session[:user] = user.email
    redirect "/" 
  else
  	user.errors.each do |e|
		puts e
	end
	register_confirm.each do |e|
		puts e
	end
  	puts "Error save user"
  	@message = {:msg => 'Error save user'}
    redirect "/signup?email=#{params[:user][:email]}"
  end
end

# activation for registering
# in case token expired, what to do , the client need to relogin and activate again
get "/activate/:token" do |token|
	if activate_token = Activation.first(:token => token.strip) then 
		user = activate_token.user
		if user.status == 0 and (activate_token.created_at - 3 <= DateTime.parse(Time.now.to_s)) then 
			user.status = 1 
			activate_token.token = Time.now.to_s
			activate_token.status = 1
		else
			@message = {:msg => 'Activation expired, please reactive'}			
			redirect '/'			
		end
		if user.save and activate_token.save then 
			@message = {:msg => 'Your acount was activated'}
			#session[:user] = user.email
			redirect "/"				
		else
			redirect "/signup?email=#{user.email}"
		end
	else
		@message = {:msg => 'Invalid token'}
		redirect "/"
	end
end
get "/reset" do
	erb :reset
end
post "/reset" do
	email = params[:user][:email].gsub(/\s+/, "")
	if email.empty?
	  	@message = {:msg => 'Email cannot be blank'}
	  	redirect '/reset'
	 end
	#newpass = generate_activation_code(8);
	if user = User.first(:email => email) then
		#user.password = Digest::MD5.hexdigest(newpass)
		reset_confirm = Activation.new(:token => SecureRandom.hex, :created_at => Time.now,
			:description => "Reset password", :status => 0)
		reset_confirm.user = user 

		if reset_confirm.save! and user.save!
			Resque.enqueue(SendEmail, email, reset_confirm.token, 'reset')
			#sendmail(user.email, register_confirm.token, :resetmail)
			@message = {:msg => 'Email sent'}
			redirect '/'
		else
			@message = {:msg => 'Reset pasword error'}
			redirect '/'
		end
	else
		@message = {:msg => 'Not exist email, please register'}
		redirect '/'
	end
end
get "/resetactivation/:token" do |token|
	#render :index
	if activate_token = Activation.first(:token => token.strip) 
		user = activate_token.user
		if activate_token.created_at - 3 <= DateTime.parse(Time.now.to_s)
			activate_token.token = Time.now.to_s
			activate_token.status = 1
		else
			@message = {:msg => 'Activation expired, please reactive'}
			redirect '/'
		end
		if user.save! and activate_token.save! then 
			@message = {:msg => 'Your acount was activated'}
			session[:user] = user.email
			redirect '/'
		else
			@message = {:msg => 'Error occur, please try again'}
			redirect '/'
		end
	else
		@message = {:msg => 'Invalid token'}
		redirect '/'
	end
end
get "/login" do
  erb :login
end

post "/login" do
  if user = User.first(:email => params[:email])
  #  if user.password_hash == BCrypt::Engine.hash_secret(params[:password], user.password_salt)
  	if user.password == hash_pass(params[:password]) then 
	    session[:user] = user.email 
	    redirect "/"
    else
    	@message = {:msg => 'Wrong password'}
      redirect "/login?email=#{params[:email]}"
    end
  else
  	@message = {:msg => "No email"}
    redirect "/login?email=#{params[:email]}"
  end
end

get "/logout" do
  session[:user] = nil
  redirect "/"
end

helpers do       
    def current_user
      @current_user ||= User.first(:email => session[:user]) if session[:user]
    end
    def h(text)
	    Rack::Utils.escape_html(text)
	end
	def generate_activation_code(size = 6)
	  charset = %w{ 2 3 4 6 7 9 A C D E F G H J K M N P Q R T V W X Y Z}
	  (0...size).map{ charset.to_a[rand(charset.size)] }.join
	end
	def hash_pass(password)
		return Digest::MD5.hexdigest(password)
	end
end

