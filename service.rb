require 'sinatra'
require 'mongoid'
require 'savon'
require 'date'
require 'time'
Mongoid.load!("config/mongoid.yml", :production);

  class Monhoc
    include Mongoid::Document
    field :mamonhoc, type: String
    field :tenmonhoc, type: String
    has_many :lopmonhocs    
  end      
  class Lopmonhoc
    include Mongoid::Document
    field :malop, type: String   
    field :malophanhchinh, type: String
    field :tengiaovien, type: String
    field :sotinchi, type: Integer
    field :maphonghoc, type: String
    field :namhoc, type: String
    field :hocky, type: Integer
    field :tungay, type: Date
    field :ngayketthuc, type: Date
    field :sotuanhoc, type: Integer
    field :tuanhocbatdau, type: Integer
    field :siso, type: Integer
    belongs_to :monhoc
    has_and_belongs_to_many :sinhviens    
    has_many :slots
  end
  class Sinhvien
    include Mongoid::Document    
    field :masinhvien, type: String 
    has_and_belongs_to_many :lopmonhocs    
    has_and_belongs_to_many :slots  
    has_many :tinhtrangs
  end  
  class Tinhtrang
    include Mongoid::Document
    field :tinhtrang, type: Integer
    belongs_to :sinhvien
    belongs_to :slot
  end
  class Slot
    include Mongoid::Document
    field :batdau, type: DateTime
    has_and_belongs_to_many :sinhviens
    belongs_to :lopmonhoc  
    has_many :tinhtrangs  
  end
  @@tiets = ['06:30','07:20','08:10','09:05','09:55','10:45','12:50','13:40','14:30','15:25','16:15','17:05'];
  @@htiets = @@tiets.map {|h| DateTime.strptime(h,"%H:%M")}  
  @@thu = {:thu2 => 0, :thu3 => 1,:thu4 => 2,:thu5 => 3,:thu6 => 4,:thu7 => 5,:thu8 => 6};  
before do      
  content_type 'application/json'
end
get '/tinhtrang' do
  Sinhvien.each do |sv|
    next if (sv.slots and sv.slots.size == 0)
    sv.slots.each do |sl|
      tt = Tinhtrang.find_or_create_by(sinhvien_id: sv.id, slot_id: sl.id)
      tt.update_attributes(tinhtrang: 0)
      sv.tinhtrangs << tt
      sl.tinhtrangs << tt      
    end
  end
end
get '/capnhattkb' do 
  client = Savon::Client.new do |wsdl, http|
    wsdl.document = "http://10.1.0.238:8082/HPUWebService.asmx?wsdl"
    http.read_timeout = 7*24*3600
  end  
  

  response = client.request(:tkb_lop_mon_hoc) ;    
  res_hash = response.body.to_hash if response and response.body;
  ls = res_hash[:tkb_lop_mon_hoc_response][:tkb_lop_mon_hoc_result][:diffgram][:document_element];   
  cc = 0
  if (ls) then         
    ls[:tkb_lop_mon_hoc].each do |item|                
      lop = Lopmonhoc.find_by(malop: item[:ma_lop].strip) rescue nil 
      puts item.inspect ; next if lop == nil      
      cc = cc + 1
      puts "process " + cc.to_s + " :" + item[:ma_lop].strip
      if (lop.sotinchi == nil) then 
        lop.update_attributes(
              tengiaovien: item[:ten_giao_vien] ? item[:ten_giao_vien].strip : '',
              maphonghoc: item[:ma_phong_hoc].is_a?(String) ? item[:ma_phong_hoc].strip : '',
              sotinchi: item[:sotc].strip,
              namhoc: item[:nam_hoc].strip,
              hocky: item[:hoc_ky].strip)   
      end   
      ngaybatdau = DateTime.strptime(item[:tu_ngay].strip,"%d/%m/%Y")                                 
      @@thu.each do |k,v|
        if item.has_key?(k) then
          index = item[k].strip.to_i-1;
          ngaybatdau = DateTime.new(ngaybatdau.year, ngaybatdau.month, ngaybatdau.day,
            @@htiets[index].hour, @@htiets[index].minute) + v;
          ngayketthuc = DateTime.strptime(item[:ngay_ket_thuc].strip,"%d/%m/%Y");
          sl = Slot.find_or_create_by(batdau: Time.parse(ngaybatdau.to_s), lopmonhoc_id: lop.id)                                  
          lop.slots << sl               
          dt = ngaybatdau
          while (dt + 7) < ngayketthuc do
            dt = DateTime.new(dt.year, dt.month, dt.day , dt.hour, dt.minute) + 7;
            sl = Slot.find_or_create_by(batdau: Time.parse(dt.to_s), lopmonhoc_id: lop.id)                
            lop.slots << sl
          end
        end
      end
    end  
  end
    
  
  return {:result => "OK"}.to_json  
end

get '/getall' do  
  #Resque.enqueue(Archive, ip, Time.now.to_s, msv, 'checkltn')
  client = Savon.client("http://10.1.0.238:8082/HPUWebService.asmx?wsdl")
  response = client.request(:sinh_vien_lop_mon_hoc) ;
  res_hash = response.body.to_hash if response and response.body;
  ls = res_hash[:sinh_vien_lop_mon_hoc_response][:sinh_vien_lop_mon_hoc_result][:diffgram][:document_element]; 
  ls[:sinh_vien_lop_mon_hoc].each do |item|
    m = Monhoc.find_or_create_by(mamonhoc: item[:ma_mon_hoc].strip)    
    m.update_attributes(tenmonhoc: item[:ten_mon_hoc].strip)
    l = Lopmonhoc.find_or_create_by(malop: item[:ma_lop].strip)        
    m.lopmonhocs << l if l != nil
    s = Sinhvien.find_or_create_by(masinhvien: item[:ma_sinh_vien].strip)    
    l.sinhviens << s if s != nil
  end  
  return {:result => ls[:sinh_vien_lop_mon_hoc][0]}.to_json  
end

get '/sinhvien/truc/?' do   
  Lopmonhoc.each do |lop|      
    puts "process " + lop.malop 
    sinhviens = lop.sinhviens.shuffle
    slots = lop.slots if lop 
    count = sinhviens.size if sinhviens
    next if count == 0
    temp = 0
    ss = slots.size
    next if ss == 0
    iid = ss/count + 1
    if (count > 0 and slots.size > 0) then
      slots.each do |slot|   
        tt = (iid < 3) ? 3 : iid;           
        tt.times do         
          if (temp >= count) then  temp = 0; end          
          sv = Sinhvien.find_by(masinhvien: sinhviens[temp].masinhvien)
          slot.sinhviens << sv 
          tt = Tinhtrang.find_or_create_by(sinhvien_id: sv.id, slot_id: slot.id)
          tt.update_attributes(tinhtrang: 0)
          sv.tinhtrangs << tt
          slot.tinhtrangs << tt   
          temp = temp + 1
        end
      end
    end
  end
  return {:res => "OK"}.to_json
end
get '/lops/?' do 
  return Lopmonhoc.all.map {|lop| lop.malop}.to_json 
end
get '/sinhviens/?' do
  return Sinhvien.all.map {|sv| sv.masinhvien}.to_json 
end
get '/lop/:malop' do |malop|
  ml = malop.strip
  lop = Lopmonhoc.find_by(malop: ml)
  return lop.slots.map {|sl| {:batdau => sl.batdau.new_offset(Rational(0, 24)), :sv => sl.sinhviens.map {
      |sv| sv.masinhvien 
    } } }.to_json
end
get '/sinhvien/:sv' do |sv|
  msv = sv.strip  
  ssv = Sinhvien.find_by(masinhvien: msv)
  puts ssv.slots[0].batdau.to_s 
  return ssv.slots.map {|sl| {:batdau => sl.batdau.new_offset(Rational(0, 24)), :lop => sl.lopmonhoc.malop } }.to_json
end

