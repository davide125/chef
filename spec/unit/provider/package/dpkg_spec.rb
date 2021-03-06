#
# Author:: Bryan McLellan (btm@loftninjas.org)
# Copyright:: Copyright (c) 2009 Bryan McLellan
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

describe Chef::Provider::Package::Dpkg do
  let(:node) { Chef::Node.new }
  let(:events) { Chef::EventDispatch::Dispatcher.new }
  let(:run_context) { Chef::RunContext.new(node, {}, events) }
  let(:package) { "wget" }
  let(:source) { "/tmp/wget_1.11.4-1ubuntu1_amd64.deb" }
  let(:new_resource) do
    new_resource = Chef::Resource::Package.new(package)
    new_resource.source source
    new_resource
  end
  let(:provider) { Chef::Provider::Package::Dpkg.new(new_resource, run_context) }

  let(:dpkg_deb_version) { "1.11.4" }
  let(:dpkg_deb_status) { status = double(:stdout => "#{package}\t#{dpkg_deb_version}", :exitstatus => 0) }
  let(:dpkg_s_version) { "1.11.4-1ubuntu1" }
  let(:dpkg_s_status) do
    stdout = <<-DPKG_S
Package: #{package}
Status: install ok installed
Priority: important
Section: web
Installed-Size: 1944
Maintainer: Ubuntu Core developers <ubuntu-devel-discuss@lists.ubuntu.com>
Architecture: amd64
Version: #{dpkg_s_version}
Config-Version: #{dpkg_s_version}
Depends: libc6 (>= 2.8~20080505), libssl0.9.8 (>= 0.9.8f-5)
Conflicts: wget-ssl
    DPKG_S
    status = double(:stdout => stdout, :exitstatus => 1)
  end

  before(:each) do
    allow(provider).to receive(:shell_out!).with("dpkg-deb -W #{new_resource.source}", timeout: 900).and_return(dpkg_deb_status)
    allow(provider).to receive(:shell_out).with("dpkg -s #{package}", timeout: 900).and_return(dpkg_s_status)
    allow(::File).to receive(:exist?).with(source).and_return(true)
  end

  describe "#define_resource_requirements" do
    it "should raise an exception if a source is supplied but not found when :install" do
      allow(::File).to receive(:exist?).with(source).and_return(false)
      expect { provider.run_action(:install) }.to raise_error(Chef::Exceptions::Package)
    end

    it "should raise an exception if a source is supplied but not found when :upgrade" do
      allow(::File).to receive(:exist?).with(source).and_return(false)
      expect { provider.run_action(:upgrade) }.to raise_error(Chef::Exceptions::Package)
    end

    # FIXME?  we're saying we ignore source, but should supplying source on :remove or :purge be an actual error?
    it "should not raise an exception if a source is supplied but not found when :remove" do
      allow(::File).to receive(:exist?).with(source).and_return(false)
      expect(provider).to receive(:action_remove)
      expect { provider.run_action(:remove) }.not_to raise_error
    end

    it "should not raise an exception if a source is supplied but not found when :purge" do
      allow(::File).to receive(:exist?).with(source).and_return(false)
      expect(provider).to receive(:action_purge)
      expect { provider.run_action(:purge) }.not_to raise_error
    end

    it "should raise an exception if a source is nil when :install" do
      new_resource.source nil
      allow(::File).to receive(:exist?).with(source).and_return(false)
      expect { provider.run_action(:install) }.to raise_error(Chef::Exceptions::Package)
    end

    it "should raise an exception if a source is nil when :upgrade" do
      new_resource.source nil
      allow(::File).to receive(:exist?).with(source).and_return(false)
      expect { provider.run_action(:upgrade) }.to raise_error(Chef::Exceptions::Package)
    end

    it "should not raise an exception if a source is nil when :remove" do
      new_resource.source nil
      allow(::File).to receive(:exist?).with(source).and_return(false)
      expect(provider).to receive(:action_remove)
      expect { provider.run_action(:remove) }.not_to raise_error
    end

    it "should not raise an exception if a source is nil when :purge" do
      new_resource.source nil
      allow(::File).to receive(:exist?).with(source).and_return(false)
      expect(provider).to receive(:action_purge)
      expect { provider.run_action(:purge) }.not_to raise_error
    end
  end

  describe "when loading the current resource state" do

    it "should create a current resource with the name of the new_resource" do
      provider.load_current_resource
      expect(provider.current_resource.package_name).to eq("wget")
    end

    describe 'gets the source package version from dpkg-deb' do
      def check_version(version)
        status = double(:stdout => "wget\t#{version}", :exitstatus => 0)
        expect(provider).to receive(:shell_out!).with("dpkg-deb -W #{new_resource.source}", timeout: 900).and_return(status)
        provider.load_current_resource
        expect(provider.current_resource.package_name).to eq("wget")
        expect(provider.candidate_version).to eq(version)
      end

      it 'if short version provided' do
        check_version('1.11.4')
      end

      it 'if extended version provided' do
        check_version('1.11.4-1ubuntu1')
      end

      it 'if distro-specific version provided' do
        check_version('1.11.4-1ubuntu1~lucid')
      end

      it 'returns the version if an epoch is used' do
        check_version('1:1.8.3-2')
      end
    end

    describe "when the package name has `-', `+' or `.' characters" do
      let(:package) { "f.o.o-pkg++2" }

      it "gets the source package name from dpkg-deb correctly" do
        provider.load_current_resource
        expect(provider.current_resource.package_name).to eq("f.o.o-pkg++2")
      end
    end

    describe "when the package version has `~', `-', `+' or `.' characters" do
      let(:package) { "b.a.r-pkg++1" }
      let(:dpkg_deb_version) { "1.2.3+3141592-1ubuntu1~lucid" }
      let(:dpkg_s_version) { "1.2.3+3141592-1ubuntu1~lucid" }

      it "gets the source package version from dpkg-deb correctly when the package version has `~', `-', `+' or `.' characters" do
        provider.load_current_resource
        expect(provider.candidate_version).to eq('1.2.3+3141592-1ubuntu1~lucid')
      end
    end

    it "should raise an exception if the source is not set but we are installing" do
      new_resource = Chef::Resource::Package.new("wget")
      provider.new_resource = new_resource
      provider.load_current_resource
      provider.define_resource_requirements
      expect { provider.run_action(:install)}.to raise_error(Chef::Exceptions::Package)
    end

    it "should return the current version installed if found by dpkg" do
      provider.load_current_resource
      expect(provider.current_resource.version).to eq("1.11.4-1ubuntu1")
    end

    it "should raise an exception if dpkg fails to run" do
      status = double(:stdout => "", :exitstatus => -1)
      expect(provider).to receive(:shell_out_with_timeout!).with("dpkg-deb -W /tmp/wget_1.11.4-1ubuntu1_amd64.deb").and_raise(Mixlib::ShellOut::ShellCommandFailed)
      expect { provider.load_current_resource }.to raise_error(Mixlib::ShellOut::ShellCommandFailed)
    end
  end

  describe Chef::Provider::Package::Dpkg, "install and upgrade" do
    it "should run dpkg -i with the package source" do
      expect(provider).to receive(:run_noninteractive).with(
        "dpkg -i /tmp/wget_1.11.4-1ubuntu1_amd64.deb"
      )
      provider.install_package("wget", "1.11.4-1ubuntu1")
    end

    it "should run dpkg -i if the package is a path and the source is nil" do
      new_resource.name = "/tmp/wget_1.11.4-1ubuntu1_amd64.deb"
      expect(provider).to receive(:run_noninteractive).with(
        "dpkg -i /tmp/wget_1.11.4-1ubuntu1_amd64.deb"
      )
      provider.install_package("/tmp/wget_1.11.4-1ubuntu1_amd64.deb", "1.11.4-1ubuntu1")
    end

    it "should run dpkg -i if the package is a path and the source is nil for an upgrade" do
      new_resource.name = "/tmp/wget_1.11.4-1ubuntu1_amd64.deb"
      expect(provider).to receive(:run_noninteractive).with(
        "dpkg -i /tmp/wget_1.11.4-1ubuntu1_amd64.deb"
      )
      provider.upgrade_package("/tmp/wget_1.11.4-1ubuntu1_amd64.deb", "1.11.4-1ubuntu1")
    end

    it "should run dpkg -i with the package source and options if specified" do
      expect(provider).to receive(:run_noninteractive).with(
        "dpkg -i --force-yes /tmp/wget_1.11.4-1ubuntu1_amd64.deb"
      )
      allow(new_resource).to receive(:options).and_return("--force-yes")

      provider.install_package("wget", "1.11.4-1ubuntu1")
    end
    it "should upgrade by running install_package" do
      expect(provider).to receive(:install_package).with("wget", "1.11.4-1ubuntu1")
      provider.upgrade_package("wget", "1.11.4-1ubuntu1")
    end
  end

  describe Chef::Provider::Package::Dpkg, "remove and purge" do
    it "should run dpkg -r to remove the package" do
      expect(provider).to receive(:run_noninteractive).with(
        "dpkg -r wget"
      )
      provider.remove_package("wget", "1.11.4-1ubuntu1")
    end

    it "should run dpkg -r to remove the package with options if specified" do
      expect(provider).to receive(:run_noninteractive).with(
        "dpkg -r --force-yes wget"
      )
      allow(new_resource).to receive(:options).and_return("--force-yes")

      provider.remove_package("wget", "1.11.4-1ubuntu1")
    end

    it "should run dpkg -P to purge the package" do
      expect(provider).to receive(:run_noninteractive).with(
        "dpkg -P wget"
      )
      provider.purge_package("wget", "1.11.4-1ubuntu1")
    end

    it "should run dpkg -P to purge the package with options if specified" do
      expect(provider).to receive(:run_noninteractive).with(
        "dpkg -P --force-yes wget"
      )
      allow(new_resource).to receive(:options).and_return("--force-yes")

      provider.purge_package("wget", "1.11.4-1ubuntu1")
    end
  end
end
