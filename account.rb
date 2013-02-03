require 'data_mapper'
require 'sinatra'
require 'securerandom'
require 'date'
require 'time'
require 'digest/md5'
require 'resque'
set :environment, :production

Resque.redis = 'localhost:6379'

#Dir[File.dirname(__FILE__) + '/workers/*.rb'].each {|file| require file }
DataMapper::Logger.new($stdout, :debug)
DataMapper.setup(:default, 'postgres://casuser:123456@10.1.0.195:5433/casauth2')

class User
  include DataMapper::Resource

	#attr_accessor :password, :password_confirmation

	property :id, Serial
	property :email, String,     :required => true, :unique => true
	
	property :created_at, DateTime 
	property :status, Integer	
	property :password, String
	#property :password_hash,  Text  
   # property :password_salt,  Text    
   # validates_presence_of         :password
   # validates_confirmation_of     :password
   # validates_length_of           :password, :min => 6

    belongs_to :role	
    has 1, :profile
    has n, :confirmations
end
class Confirmation
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

class SendMail
  @queue = :email

  def self.perform(to, token, reason)	
  		puts "sending email to #{to} with token #{token} with reason #{reason}" 

     Pony.mail(:to => to, :from => 'hoangdung1987@gmail.com', :via => :smtp, :smtp => {
	  :host     => 'smtp.gmail.com',
	  :port     => '587',
	  :user     => 'hoangdung1987@gmail.com',
	  :password => 'revskill123',
	  :auth     => :plain,           # :plain, :login, :cram_md5, no auth by default
	  :domain   => "localhost:3002"     # the HELO domain provided by the client to the server
	}, :body => erb(reason))

  #   Tire.index 'emaillog' do      
   #   create
    #  store :email_to => to,   :time => Time.now, :token => token, :reason => reason
     # refresh
    #end
	
  end
end

get "/signup" do
  erb :signup
end

get "/" do
	erb :index
end





post "/signup" do
  email = params[:user][:email].gsub(/\s+/, "")
  user = User.create({:email => email, :password => Digest::MD5.hexdigest(params[:user][:password]),
  	:status => 0})
  register_confirm = Confirmation.create({:token = SecureRandom.hex, :created_at => Time.now, 
  	:description => 'Register confirmation', :status => 0})
  user.confirmations << register_confirm
  user.save!
  #SendEmail.perform_async(email, user.token)
  Resque.enqueue(SendEmail, email, register_confirm.token, :registermail)
  #user.password_salt = BCrypt::Engine.generate_salt
  #user.password_hash = BCrypt::Engine.hash_secret(params[:user][:password], user.password_salt)
  if user.save and register_confirm.save
    session[:user] = user.email
    redirect "/" 
  else
    redirect "/signup?email=#{params[:user][:email]}"
  end
end
get "/confirm/:token" do |token|
	if confirm = Confirmation.first(:token => token.strip) then 
		user = confirm.user
		if user.status == 0 then 
			user.status = 1 
			confirm.status = 1
		end		
		if user.save and confirm.save then 
			session[:user] = user.email
			redirect "/"				
		else
			redirect "/signup?email=#{user.email}"
		end
	else
		redirect "/"
	end
end
get "/reset" do
	erb :reset
end
post "/reset" do
	email = params[:user][:email].gsub(/\s+/, "")
	newpass = generate_activation_code(8);
	if user = User.first(:email => email) then
		reset_confirm = Confirmation.create({:token => SecureRandom.hex, created_at => Time.now,
			:description => "Reset password", :status => 0})
		reset_confirm.user = user 

		if reset_confirm.save
			Resque.enqueue(SendEmail, email, user.token, :resetmail)
		end
	end
end
get "/reset/:token" do |token|

end
get "/login" do
  erb :login
end

post "/login" do
  if user = User.first(:email => params[:email])
  #  if user.password_hash == BCrypt::Engine.hash_secret(params[:password], user.password_salt)
  	if user.password == params[:password] then 
	    session[:user] = user.email 
	    redirect "/"
    else
      redirect "/login?email=#{params[:email]}"
    end
  else
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
end

