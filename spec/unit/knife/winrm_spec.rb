#
# Author:: Bryan McLellan <btm@opscode.com>
# Copyright:: Copyright (c) 2013 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'spec_helper'

Chef::Knife::Winrm.load_deps

describe Chef::Knife::Winrm do
  before(:all) do
    @original_config = Chef::Config.hash_dup
    @original_knife_config = Chef::Config[:knife].nil? ? nil : Chef::Config[:knife].dup
  end

  after(:all) do
    Chef::Config.configuration = @original_config
    Chef::Config[:knife] = @original_knife_config if @original_knife_config
  end

  before do
    @knife = Chef::Knife::Winrm.new
    @knife.config[:attribute] = "fqdn"
    @node_foo = Chef::Node.new
    @node_foo.automatic_attrs[:fqdn] = "foo.example.org"
    @node_foo.automatic_attrs[:ipaddress] = "10.0.0.1"
    @node_bar = Chef::Node.new
    @node_bar.automatic_attrs[:fqdn] = "bar.example.org"
    @node_bar.automatic_attrs[:ipaddress] = "10.0.0.2"
    @node_bar.automatic_attrs[:ec2][:public_hostname] = "somewhere.com"
  end

  describe "#configure_session" do
    before do
      @query = double("Chef::Search::Query")
    end

    context "when there are some hosts found but they do not have an attribute to connect with" do
      before do
        @knife.config[:manual] = false
        @knife.config[:winrm_password] = 'P@ssw0rd!'
        allow(@query).to receive(:search).and_return([[@node_foo, @node_bar]])
        @node_foo.automatic_attrs[:fqdn] = nil
        @node_bar.automatic_attrs[:fqdn] = nil
        allow(Chef::Search::Query).to receive(:new).and_return(@query)
      end

      it "raises a specific error (KNIFE-222)" do
        expect(@knife.ui).to receive(:fatal).with(/does not have the required attribute/)
        expect(@knife).to receive(:exit).with(10)
        @knife.configure_chef
        @knife.resolve_target_nodes
      end
    end

    context "when there are nested attributes" do
      before do
        @knife.config[:manual] = false
        @knife.config[:winrm_password] = 'P@ssw0rd!'
        allow(@query).to receive(:search).and_return([[@node_foo, @node_bar]])
        allow(Chef::Search::Query).to receive(:new).and_return(@query)
      end

      it "uses the nested attributes (KNIFE-276)" do
        @knife.config[:attribute] = "ec2.public_hostname"
        @knife.configure_chef
        @knife.resolve_target_nodes
      end
    end

    describe Chef::Knife::Winrm do
      context "when configuring the WinRM transport" do
        before(:all) do
          @winrm_session = Object.new
          @winrm_session.define_singleton_method(:set_timeout){|timeout| ""}
        end
        after(:each) do
          Chef::Config.configuration = @original_config
          Chef::Config[:knife] = @original_knife_config if @original_knife_config
        end

        context "on windows workstations" do
          let(:winrm_command_windows_http) { Chef::Knife::Winrm.new(['-m', 'localhost', '-x', 'testuser', '-P', 'testpassword',  'echo helloworld'])        }
          it "defaults to negotiate when on a Windows host" do
            allow(Chef::Platform).to receive(:windows?).and_return(true)
            expect(winrm_command_windows_http).to receive(:load_windows_specific_gems)
            expect(Chef::Knife::WinrmSession).to receive(:new).with(hash_including(:transport => :sspinegotiate)).and_call_original
            expect(WinRM::WinRMWebService).to receive(:new).with('http://localhost:5985/wsman', anything, anything).and_return(@winrm_session)
            winrm_command_windows_http.configure_chef
            winrm_command_windows_http.configure_session
          end
        end

        context "on non-windows workstations" do
          before do
            allow(Chef::Platform).to receive(:windows?).and_return(false)
          end

          let(:winrm_command_http) { Chef::Knife::Winrm.new(['-m', 'localhost', '-x', 'testuser', '-P', 'testpassword', '-t', 'plaintext', '--winrm-authentication-protocol', 'basic', 'echo helloworld']) }

          it "defaults to the http uri scheme" do
            expect(Chef::Knife::WinrmSession).to receive(:new).with(hash_including(:transport => :plaintext)).and_call_original
            expect(WinRM::WinRMWebService).to receive(:new).with('http://localhost:5985/wsman', anything, anything).and_return(@winrm_session)
            winrm_command_http.configure_chef
            winrm_command_http.configure_session
          end

          it "sets the operation timeout and verifes default" do
            expect(Chef::Knife::WinrmSession).to receive(:new).with(hash_including(:transport => :plaintext)).and_call_original
            expect(WinRM::WinRMWebService).to receive(:new).with('http://localhost:5985/wsman', anything, anything).and_return(@winrm_session)
            expect(@winrm_session).to receive(:set_timeout).with(1800)
            winrm_command_http.configure_chef
            winrm_command_http.configure_session
          end

          it "sets the user specified winrm port" do
            Chef::Config[:knife] = {winrm_port: "5988"}
            expect(Chef::Knife::WinrmSession).to receive(:new).with(hash_including(:transport => :plaintext)).and_call_original
            expect(WinRM::WinRMWebService).to receive(:new).with('http://localhost:5988/wsman', anything, anything).and_return(@winrm_session)
            winrm_command_http.configure_chef
            winrm_command_http.configure_session
          end

          let(:winrm_command_timeout) { Chef::Knife::Winrm.new(['-m', 'localhost', '-x', 'testuser', '-P', 'testpassword', '--winrm-authentication-protocol', 'basic', '--session-timeout', '10', 'echo helloworld']) }

          it "sets operation timeout and verify 10 Minute timeout" do
            expect(Chef::Knife::WinrmSession).to receive(:new).with(hash_including(:transport => :plaintext)).and_call_original
            expect(WinRM::WinRMWebService).to receive(:new).with('http://localhost:5985/wsman', anything, anything).and_return(@winrm_session)
            expect(@winrm_session).to receive(:set_timeout).with(600)
            winrm_command_timeout.configure_chef
            winrm_command_timeout.configure_session
          end

          let(:winrm_command_https) { Chef::Knife::Winrm.new(['-m', 'localhost', '-x', 'testuser', '-P', 'testpassword', '--winrm-transport', 'ssl', 'echo helloworld']) }

          it "uses the https uri scheme if the ssl transport is specified" do
            Chef::Config[:knife] = {:winrm_transport => 'ssl'}
            expect(Chef::Knife::WinrmSession).to receive(:new).with(hash_including(:transport => :ssl)).and_call_original
            expect(WinRM::WinRMWebService).to receive(:new).with('https://localhost:5986/wsman', anything, anything).and_return(@winrm_session)
            winrm_command_https.configure_chef
            winrm_command_https.configure_session
          end

          it "uses the winrm port '5986' by default for ssl transport" do
            Chef::Config[:knife] = {:winrm_transport => 'ssl'}
            expect(Chef::Knife::WinrmSession).to receive(:new).with(hash_including(:transport => :ssl)).and_call_original
            expect(WinRM::WinRMWebService).to receive(:new).with('https://localhost:5986/wsman', anything, anything).and_return(@winrm_session)
            winrm_command_https.configure_chef
            winrm_command_https.configure_session
          end

          it "defaults to validating the server when the ssl transport is used" do
            expect(Chef::Knife::WinrmSession).to receive(:new).with(hash_including(:transport => :ssl)).and_call_original
            expect(WinRM::WinRMWebService).to receive(:new).with(anything, anything, hash_including(:no_ssl_peer_verification => false)).and_return(@winrm_session)
            winrm_command_https.configure_chef
            winrm_command_https.configure_session
          end

          let(:winrm_command_verify_peer) { Chef::Knife::Winrm.new(['-m', 'localhost', '-x', 'testuser', '-P', 'testpassword', '--winrm-transport', 'ssl', '--winrm-ssl-verify-mode', 'verify_peer', 'echo helloworld'])}

          it "validates the server when the ssl transport is used and the :winrm_ssl_verify_mode option is not configured to :verify_none" do
            expect(Chef::Knife::WinrmSession).to receive(:new).with(hash_including(:transport => :ssl)).and_call_original
            expect(WinRM::WinRMWebService).to receive(:new).with(anything, anything, hash_including(:no_ssl_peer_verification => false)).and_return(@winrm_session)
            winrm_command_verify_peer.configure_chef
            winrm_command_verify_peer.configure_session
          end

          let(:winrm_command_no_verify) { Chef::Knife::Winrm.new(['-m', 'localhost', '-x', 'testuser', '-P', 'testpassword', '--winrm-transport', 'ssl', '--winrm-ssl-verify-mode', 'verify_none', 'echo helloworld'])}

          it "does not validate the server when the ssl transport is used and the :winrm_ssl_verify_mode option is set to :verify_none" do
            expect(Chef::Knife::WinrmSession).to receive(:new).with(hash_including(:transport => :ssl)).and_call_original
            expect(WinRM::WinRMWebService).to receive(:new).with(anything, anything, hash_including(:no_ssl_peer_verification => true)).and_return(@winrm_session)
            winrm_command_no_verify.configure_chef
            winrm_command_no_verify.configure_session
          end

          it "prints warning output when the :winrm_ssl_verify_mode set to :verify_none to disable server validation" do
            expect(Chef::Knife::WinrmSession).to receive(:new).with(hash_including(:transport => :ssl)).and_call_original
            expect(WinRM::WinRMWebService).to receive(:new).with(anything, anything, hash_including(:no_ssl_peer_verification => true)).and_return(@winrm_session)
            expect(winrm_command_no_verify).to receive(:warn_no_ssl_peer_verification)

            winrm_command_no_verify.configure_chef
            winrm_command_no_verify.configure_session
          end

          let(:winrm_command_ca_trust) { Chef::Knife::Winrm.new(['-m', 'localhost', '-x', 'testuser', '-P', 'testpassword', '--winrm-transport', 'ssl', '--ca-trust-file', '~/catrustroot', '--winrm-ssl-verify-mode', 'verify_none', 'echo helloworld'])}

          it "validates the server when the ssl transport is used and the :ca_trust_file option is specified even if the :winrm_ssl_verify_mode option is set to :verify_none" do
            expect(Chef::Knife::WinrmSession).to receive(:new).with(hash_including(:transport => :ssl)).and_call_original
            expect(WinRM::WinRMWebService).to receive(:new).with(anything, anything, hash_including(:no_ssl_peer_verification => false)).and_return(@winrm_session)
            winrm_command_ca_trust.configure_chef
            winrm_command_ca_trust.configure_session
          end
        end
      end

      context "when executing the run command which sets the process exit code" do
        before(:each) do
          Chef::Config[:knife] = {:winrm_transport => 'plaintext'}
          @winrm = Chef::Knife::Winrm.new(['-m', 'localhost', '-x', 'testuser', '-P', 'testpassword', '--winrm-authentication-protocol', 'basic', 'echo helloworld'])
        end

        after(:each) do
          Chef::Config.configuration = @original_config
          Chef::Config[:knife] = @original_knife_config if @original_knife_config
        end

        it "returns with 0 if the command succeeds" do
          allow(@winrm).to receive(:relay_winrm_command).and_return(0)
          return_code = @winrm.run
          expect(return_code).to be_zero
        end

        it "exits with exact exit status if the command fails and returns config is set to 0" do
          command_status = 510
          session_mock = Chef::Knife::WinrmSession.new({:transport => :plaintext, :host => 'localhost', :port => '5985'})

          @winrm.config[:returns] = "0"
          Chef::Config[:knife][:returns] = [0]

          allow(@winrm).to receive(:relay_winrm_command)
          allow(@winrm.ui).to receive(:error)
          allow(Chef::Knife::WinrmSession).to receive(:new).and_return(session_mock)
          allow(session_mock).to receive(:exit_code).and_return(command_status)
          expect { @winrm.run_with_pretty_exceptions }.to raise_error(SystemExit) { |e| expect(e.status).to eq(command_status) }
        end

        it "exits with non-zero status if the command fails and returns config is set to 0" do
          command_status = 1
          @winrm.config[:returns] = "0,53"
          Chef::Config[:knife][:returns] = [0,53]
          allow(@winrm).to receive(:relay_winrm_command).and_return(command_status)
          allow(@winrm.ui).to receive(:error)
          session_mock = Chef::Knife::WinrmSession.new({:transport => :plaintext, :host => 'localhost', :port => '5985'})
          allow(Chef::Knife::WinrmSession).to receive(:new).and_return(session_mock)
          allow(session_mock).to receive(:exit_code).and_return(command_status)
          expect { @winrm.run_with_pretty_exceptions }.to raise_error(SystemExit) { |e| expect(e.status).to eq(command_status) }
        end

        it "exits with a zero status if the command returns an expected non-zero status" do
          command_status = 53
          Chef::Config[:knife][:returns] = [0,53]
          allow(@winrm).to receive(:relay_winrm_command).and_return(command_status)
          session_mock = Chef::Knife::WinrmSession.new({:transport => :plaintext, :host => 'localhost', :port => '5985'})
          allow(Chef::Knife::WinrmSession).to receive(:new).and_return(session_mock)
          allow(session_mock).to receive(:exit_codes).and_return({"thishost" => command_status})
          exit_code = @winrm.run
          expect(exit_code).to be_zero
        end

        it "exits with a zero status if the command returns an expected non-zero status" do
          command_status = 53
          @winrm.config[:returns] = '0,53'
          allow(@winrm).to receive(:relay_winrm_command).and_return(command_status)
          session_mock = Chef::Knife::WinrmSession.new({:transport => :plaintext, :host => 'localhost', :port => '5985'})
          allow(Chef::Knife::WinrmSession).to receive(:new).and_return(session_mock)
          allow(session_mock).to receive(:exit_codes).and_return({"thishost" => command_status})
          exit_code = @winrm.run
          expect(exit_code).to be_zero
        end

        it "exits with 100 if command execution raises an exception other than 401" do
          allow(@winrm).to receive(:relay_winrm_command).and_raise(WinRM::WinRMHTTPTransportError.new('', '500'))
          allow(@winrm.ui).to receive(:error)
          expect { @winrm.run_with_pretty_exceptions }.to raise_error(SystemExit) { |e| expect(e.status).to eq(100) }
        end

        it "exits with 100 if command execution raises a 401" do
          allow(@winrm).to receive(:relay_winrm_command).and_raise(WinRM::WinRMHTTPTransportError.new('', '401'))
          allow(@winrm.ui).to receive(:info)
          allow(@winrm.ui).to receive(:error)
          expect { @winrm.run_with_pretty_exceptions }.to raise_error(SystemExit) { |e| expect(e.status).to eq(100) }
        end

        it "exits with 0 if command execution raises a 401 and suppress_auth_failure is set to true" do
          @winrm.config[:suppress_auth_failure] = true
          allow(@winrm).to receive(:relay_winrm_command).and_raise(WinRM::WinRMHTTPTransportError.new('', '401'))
          exit_code = @winrm.run_with_pretty_exceptions
          expect(exit_code).to eq(401)
        end

        context "when winrm_authentication_protocol specified" do
          before do
            Chef::Config[:knife] = {:winrm_transport => 'plaintext'}
            allow(@winrm).to receive(:relay_winrm_command).and_return(0)
          end

          it "sets sspinegotiate transport on windows for 'negotiate' authentication" do
            @winrm.config[:winrm_authentication_protocol] = "negotiate"
            allow(Chef::Platform).to receive(:windows?).and_return(true)
            allow(@winrm).to receive(:require).with('winrm-s').and_return(true)
            expect(@winrm).to receive(:create_winrm_session).with({:user=>"testuser", :password=>"testpassword", :port=>"5985", :no_ssl_peer_verification => false, :basic_auth_only=>false, :operation_timeout=>1800, :transport=>:sspinegotiate, :disable_sspi=>false, :host=>"localhost"})
            exit_code = @winrm.run
          end

          it "does not have winrm opts transport set to sspinegotiate for unix" do
            @winrm.config[:winrm_authentication_protocol] = "negotiate"
            allow(Chef::Platform).to receive(:windows?).and_return(false)
            allow(@winrm).to receive(:exit)
            expect(@winrm).to receive(:create_winrm_session).with({:user=>"testuser", :password=>"testpassword", :port=>"5985", :no_ssl_peer_verification=>false, :basic_auth_only=>false, :operation_timeout=>1800, :transport=>:plaintext, :disable_sspi=>true, :host=>"localhost"})
            exit_code = @winrm.run
          end

          it "applies winrm monkey patch on windows if 'negotiate' authentication and 'plaintext' transport is specified", :windows_only => true do
            @winrm.config[:winrm_authentication_protocol] = "negotiate"
            allow(Chef::Platform).to receive(:windows?).and_return(true)
            allow(@winrm.ui).to receive(:warn)
            expect(@winrm).to receive(:require).with('winrm-s').and_call_original
            @winrm.run
          end

          it "raises an error if value is other than [basic, negotiate, kerberos]" do
            @winrm.config[:winrm_authentication_protocol] = "invalid"
            allow(Chef::Platform).to receive(:windows?).and_return(true)
            expect(@winrm.ui).to receive(:error)
            expect { @winrm.run }.to raise_error(SystemExit)
          end

          it "skips the winrm monkey patch for 'basic' authentication" do
            @winrm.config[:winrm_authentication_protocol] = "basic"
            allow(Chef::Platform).to receive(:windows?).and_return(true)
            expect(@winrm).to_not receive(:require).with('winrm-s')
            @winrm.run
          end

          it "skips the winrm monkey patch for 'kerberos' authentication" do
            @winrm.config[:winrm_authentication_protocol] = "kerberos"
            allow(Chef::Platform).to receive(:windows?).and_return(true)
            expect(@winrm).to_not receive(:require).with('winrm-s')
            @winrm.run
          end

          it "skips the winrm monkey patch for 'ssl' transport and 'negotiate' authentication" do
            @winrm.config[:winrm_authentication_protocol] = "negotiate"
            @winrm.config[:winrm_transport] = "ssl"
            allow(Chef::Platform).to receive(:windows?).and_return(true)
            expect(@winrm).to_not receive(:require).with('winrm-s')
            @winrm.run
          end

          it "disables sspi and skips the winrm monkey patch for 'ssl' transport and 'basic' authentication" do
            @winrm.config[:winrm_authentication_protocol] = "basic"
            @winrm.config[:winrm_transport] = "ssl"
            @winrm.config[:winrm_port] = "5986"
            allow(Chef::Platform).to receive(:windows?).and_return(true)
            expect(@winrm).to receive(:create_winrm_session).with({:user=>"testuser", :password=>"testpassword", :port=>"5986", :no_ssl_peer_verification=>false, :basic_auth_only=>true, :operation_timeout=>1800, :transport=>:ssl, :disable_sspi=>true, :host=>"localhost"})
            expect(@winrm).to_not receive(:require).with('winrm-s')
            @winrm.run
          end

          it "prints a warning and exits on linux for unencrypted negotiate authentication" do
            @winrm.config[:winrm_authentication_protocol] = "negotiate"
            @winrm.config[:winrm_transport] = "plaintext"
            allow(Chef::Platform).to receive(:windows?).and_return(false)
            expect(@winrm).to_not receive(:require).with('winrm-s')
            expect(@winrm.ui).to receive(:warn).twice
            expect { @winrm.run }.to raise_error(SystemExit)
          end
        end
      end
    end
  end
end
