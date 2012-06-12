names = ['truong', 'george', 'huy']
names.each do |x|
	if x == 'george'
		puts 'Break!'
		break
	end
	puts x
end