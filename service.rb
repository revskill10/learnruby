require 'sinatra'
require 'mongoid'
require 'savon'
require 'date'
require 'time'
Mongoid.load!("mongoid_service.yml", :production);

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
  end
  class Slot
    include Mongoid::Document
    field :batdau, type: DateTime
    has_and_belongs_to_many :sinhviens
    belongs_to :lopmonhoc    
  end
  @@tiets = ['6:30','7:20','8:10','9:05','9:55','10:45','12:50','13:40','14:30','15:25','16:15','17:05'];
  @@htiets = @@tiets.map {|h| DateTime.strptime(h,"%H:%M")}  
  @@thu = {:thu2 => 0, :thu3 => 1,:thu4 => 2,:thu5 => 3,:thu6 => 4,:thu7 => 5,:thu8 => 6};  
before do      
  content_type 'application/json'
end


get '/getall' do  
  #Resque.enqueue(Archive, ip, Time.now.to_s, msv, 'checkltn')
  client = Savon.client("http://10.1.0.238:8082/HPUWebService.asmx?wsdl")
  response = client.request(:sinh_vien_lop_mon_hoc) ;
  res_hash = response.body.to_hash if response and response.body;
  ls = res_hash[:sinh_vien_lop_mon_hoc_response][:sinh_vien_lop_mon_hoc_result][:diffgram][:document_element]; 
  ls[:sinh_vien_lop_mon_hoc].each do |item|
    m = Monhoc.find_or_create_by(mamonhoc: item[:ma_mon_hoc].strip)    
    l = Lopmonhoc.find_or_create_by(malop: item[:ma_lop].strip)        
    m.lopmonhocs << l
    s = Sinhvien.find_or_create_by(masinhvien: item[:ma_sinh_vien].strip)    
    l.sinhviens << s
  end  
  return {:result => ls[:sinh_vien_lop_mon_hoc][0]}.to_json  
end

get '/capnhattkb' do 
  client = Savon::Client.new do |wsdl, http|
    wsdl.document = "http://10.1.0.238:8082/HPUWebService.asmx?wsdl"
    http.read_timeout = 24*3600
  end
  
  Sinhvien.each do |sv| 
    msv = sv.masinhvien        
    response = client.request(:tkb) do
      soap.body = {:masinhvien => msv}
    end  
    res_hash = response.body.to_hash if response and response.body;
    ls = res_hash[:tkb_response][:tkb_result][:diffgram][:document_element]; 
    if (ls ) then 
      temp = ls[:tkb];
      if (temp.is_a?(Hash)) then 
        ls = Array.new
        ls.push(temp);
      else (temp.is_a?(Array))
        ls = temp;
      end
    else 
      puts "1 mon: " + msv;
      #return '{"error":"error1"} '
    end
    puts "processing " + msv;
    if (ls) then 
      ls.each do |item|        
        ngaybatdau = DateTime.strptime(item[:tu_ngay].strip,"%d/%m/%Y")
        lop = Lopmonhoc.find_by(malop: item[:ma_lop].strip)        
        @@thu.each do |k,v|
          if item.has_key?(k) then
            index = item[k].strip.to_i-1;
            ngaybatdau = DateTime.new(ngaybatdau.year, ngaybatdau.month, ngaybatdau.day,
              @@htiets[index].hour, @@htiets[index].minute) + v;
            ngayketthuc1 = DateTime.strptime(item[:ngay_ket_thuc].strip,"%d/%m/%Y");
            sl = Slot.find_or_create_by(batdau: Time.parse(ngaybatdau.to_s), lopmonhoc_id: lop.id)                                  
            lop.slots << sl   
            lop.update_attributes(tungay: Time.parse(DateTime.strptime(item[:tu_ngay].strip,"%d/%m/%Y").to_s),
                tengiaovien: item[:ten_giao_vien] ? item[:ten_giao_vien].strip : '',
                maphonghoc: item[:ma_phong_hoc].instance_of?(String) ? item[:ma_phong_hoc].strip : '',
                sotinchi: item[:sotc].strip,
                namhoc: item[:nam_hoc].strip,
                hocky: item[:hoc_ky].strip,
                sotuanhoc: item[:so_tuan_hoc].strip,
                ngayketthuc: Time.parse(ngayketthuc1.to_s),
                siso: lop.sinhviens.size)                 
            dt = ngaybatdau
            while (dt + 7) <= ngayketthuc1 do
              dt = DateTime.new(dt.year, dt.month, dt.day , dt.hour, dt.minute) + 7;
              sl = Slot.find_or_create_by(batdau: Time.parse(dt.to_s), lopmonhoc_id: lop.id)                
              lop.slots << sl
            end
          end
        end
      end  
    end
  end
  return {:result => ls}.to_json  
end
 

get '/sinhvien/:malop' do |malop|
  lop = Lopmonhoc.find_by(malop: malop.strip)
  sinhviens = lop.sinhviens
  slots = lop.slots
  count = sinhviens.size
  temp = 0
  if (count > 0 and slots.size > 0) then
    slots.each do |slot|      
      3.times do         
        if (temp >= count) then  temp = 0; end
        slot.sinhviens << sinhviens[temp]
        temp = temp + 1
      end
    end
  end
  return lop.slots.map {|sl| sl.sinhviens.map {|sv| sv.masinhvien} }.to_json
end
get '/slots/:malop' do |malop|
  lop = Lopmonhoc.find_by(malop: malop.strip)
  return lop.slots.map {|sl| sl.batdau }.to_json
end


