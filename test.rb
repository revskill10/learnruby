require 'sinatra'
require 'mongoid'
require 'savon'

Mongoid.load!("config/mongoid.yml", :production);

  class Monhoc
    include Mongoid::Document
    field :mamonhoc, type: String
    field :tenmonhoc, type: String
    has_many :lopmonhocs
  end  
  
  class Slot
    include Mongoid::Document
    field :ngay, type: Date
    has_and_belongs_to_many :sinhviens   
    has_and_belongs_to_many :lopmonhocs   
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
    belongs_to :monhoc
    has_and_belongs_to_many :sinhviens
    has_and_belongs_to_many :slots
  end
  class Sinhvien
    include Mongoid::Document    
    field :masinhvien
    has_and_belongs_to_many :lopmonhocs
    has_and_belongs_to_many :slots
  end
    

before do      
  content_type 'application/json'
end
get '/fetchall' do  
  #Resque.enqueue(Archive, ip, Time.now.to_s, msv, 'checkltn')
  client = Savon.client("http://10.1.0.238:8082/HPUWebService.asmx?wsdl")
  response = client.request(:sinh_vien_lop_mon_hoc) ;
  res_hash = response.body.to_hash if response and response.body;
  ls = res_hash[:sinh_vien_lop_mon_hoc_response][:sinh_vien_lop_mon_hoc_result][:diffgram][:document_element]; 
  ls[:sinh_vien_lop_mon_hoc].each do |item|   
    l = Lopmonhoc.find_by(ma_lop: item[:ma_lop].strip)    
    l.update_attribute(malophanhchinh: item[:ma_lop_hanh_chinh])    
  end  
  return {:result => ls[:sinh_vien_lop_mon_hoc][0]}.to_json  
end
get '/getall' do  
  #Resque.enqueue(Archive, ip, Time.now.to_s, msv, 'checkltn')
  client = Savon.client("http://10.1.0.238:8082/HPUWebService.asmx?wsdl")
  response = client.request(:sinh_vien_lop_mon_hoc) ;
  res_hash = response.body.to_hash if response and response.body;
  ls = res_hash[:sinh_vien_lop_mon_hoc_response][:sinh_vien_lop_mon_hoc_result][:diffgram][:document_element]; 
  ls[:sinh_vien_lop_mon_hoc].each do |item|
    m = Monhoc.find_or_create_by(mamonhoc: item[:ma_mon_hoc].strip)    
    l = Lopmonhoc.find_or_create_by(ma_lop: item[:ma_lop].strip)    
    l.update_attribute(malophanhchinh: item[:ma_lop_hanh_chinh])
    m.lopmonhocs << l
    s = Sinhvien.find_or_create_by(masinhvien: item[:ma_sinh_vien].strip)    
    l.sinhviens << s
  end  
  return {:result => ls[:sinh_vien_lop_mon_hoc][0]}.to_json  
end

get '/:id' do |id|
  msv = id.strip
  client = Savon.client("http://10.1.0.238:8082/HPUWebService.asmx?wsdl")
  response = client.request(:tkb) do
    soap.body = {:ma_sinh_vien => msv}
  end  
  res_hash = response.body.to_hash if response and response.body;
  ls = res_hash[:tkb_response][:tkb_result][:diffgram][:document_element]; 
  return {:result => ls[:tkb]}.to_json  
end
get '/monhoc/:monhoc' do |monhoc|
  mamon = monhoc.strip
  m = Monhoc.find_by(mamonhoc: mamon)
  return {"m" => m.lopmonhocs }.to_json
end
   




