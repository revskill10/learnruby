require 'pony'
class SendEmail
  @queue = :email

  def self.perform(to, token, reason)  
  		puts "sending email to #{to} with token #{token} with reason #{reason}"  
      if reason == 'register'     
        body = 'Click  <a href="http://10.1.0.195:3002/activate/' +token+'>here</a> to confirm registration.'
      else
        body = 'Click  <a href="http://10.1.0.195:3002/resetactivation/' +token+'>here</a> to reset password.'
      end

      Pony.mail :to => to,
:from => 'hoangdung1987@gmail.com',
:subject => 'Registration confirmation',
:body=>  body,
:via => :smtp,
:smtp => {
:host => 'smtp.gmail.com',
:port => '587',
:tls => true,
:user => 'hoangdung1987@gmail.com',
:password => 'revskill123',
:auth => :plain,
:domain => "localhost:3002"
}

  #   Tire.index 'emaillog' do      
   #   create
    #  store :email_to => to,   :time => Time.now, :token => token, :reason => reason
     # refresh
    #end
	
  end
end
