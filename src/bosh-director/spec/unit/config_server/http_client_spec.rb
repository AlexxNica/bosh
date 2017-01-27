require 'spec_helper'
require 'httpclient'

describe Bosh::Director::ConfigServer::HTTPClient do
  class MockSuccessResponse < Net::HTTPSuccess
    attr_accessor :body

    def initialize
      super(nil, Net::HTTPOK, nil)
    end
  end

  class MockFailedResponse < Net::HTTPClientError
    def initialize
      super(nil, Net::HTTPNotFound, nil)
    end
  end

  let(:mock_config_store) do
    {
        'value' => {value: 123},
        'instance_val' => {value: 'test1'},
        'job_val' => {value: 'test2'},
        'env_val' => {value: 'test3'},
        'name_val' => {value: 'test4'}
    }
  end

  let(:config_server_hash) do
    {
        'url' => 'http://127.0.0.1:8080',
    }
  end

  let(:mock_http) { double('Net::HTTP') }

  let(:mock_response) do
    response = MockSuccessResponse.new
    response.body = 'some_response'
    response
  end

  before do
    expect(mock_http).to receive(:use_ssl=)
    expect(mock_http).to receive(:verify_mode=)
    allow(mock_http).to receive(:cert_store=)

    allow(Net::HTTP).to receive(:new) { mock_http }

    allow(Bosh::Director::Config).to receive(:config_server).and_return(config_server_hash)

    auth_provider_double = instance_double(Bosh::Director::UAAAuthProvider)
    allow(auth_provider_double).to receive(:auth_header).and_return('fake-auth-header')
    allow(Bosh::Director::UAAAuthProvider).to receive(:new).and_return(auth_provider_double)
  end

  describe '#initialize' do

    shared_examples 'cert_store' do
      store_double = nil

      before do
        store_double = instance_double(OpenSSL::X509::Store)
        allow(store_double).to receive(:set_default_paths)
        allow(OpenSSL::X509::Store).to receive(:new).and_return(store_double)
      end

      it 'uses default cert_store' do
        expect(mock_http).to receive(:cert_store=)
        expect(store_double).to receive(:set_default_paths)

        subject
      end
    end

    context 'ca_cert file does not exist' do
      before do
        config_server_hash['ca_cert_path'] = nil
      end

      it_behaves_like 'cert_store'
    end

    context 'ca_cert file exists and is empty' do
      before do
        config_server_hash['ca_cert_path'] = '/root/cert.crt'
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:read).and_return('')
      end

      it_behaves_like 'cert_store'
    end

  end

  describe '#get_by_id' do
    it 'makes a GET call using "id" resource' do
      expect(mock_http).to receive(:get).with('/v1/data/boo', {'Authorization' => 'fake-auth-header'}).and_return(mock_response)
      expect(subject.get_by_id('boo')).to eq(mock_response)
    end
  end

  describe '#get' do
    it "makes a GET call using 'name' query parameter for variable name and 'current' query parameter set to true" do
      expect(mock_http).to receive(:get).with('/v1/data?name=smurf_key&current=true', {'Authorization' => 'fake-auth-header'}).and_return(mock_response)
      expect(subject.get('smurf_key')).to eq(mock_response)
    end
  end

  describe '#post' do
    let(:request_body) do
      {
          'stuff' => 'hello'
      }
    end

    it 'makes a POST call to config server @ /v1/data/{key} with body and returns response' do
      expect(mock_http).to receive(:post).with('/v1/data', Yajl::Encoder.encode(request_body), {'Authorization' => 'fake-auth-header', 'Content-Type' => 'application/json'}).and_return(mock_response)
      expect(subject.post(request_body)).to eq(mock_response)
    end
  end
end