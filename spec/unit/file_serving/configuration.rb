#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../../spec_helper'

require 'puppet/file_serving/configuration'

describe Puppet::FileServing::Configuration do
    it "should make :new a private method" do
        proc { Puppet::FileServing::Configuration.new }.should raise_error
    end

    it "should return the same configuration each time :create is called" do
        Puppet::FileServing::Configuration.create.should equal(Puppet::FileServing::Configuration.create)
    end

    it "should have a method for removing the current configuration instance" do
        old = Puppet::FileServing::Configuration.create
        Puppet::Util::Cacher.expire
        Puppet::FileServing::Configuration.create.should_not equal(old)
    end

    after do
        Puppet::Util::Cacher.expire
    end
end

describe Puppet::FileServing::Configuration do

    before :each do
        @path = "/path/to/configuration/file.conf"
        Puppet.settings.stubs(:value).with(:trace).returns(false)
        Puppet.settings.stubs(:value).with(:fileserverconfig).returns(@path)
    end

    after :each do
        Puppet::Util::Cacher.expire
    end

    describe "when initializing" do

        it "should work without a configuration file" do
            FileTest.stubs(:exists?).with(@path).returns(false)
            proc { Puppet::FileServing::Configuration.create }.should_not raise_error
        end

        it "should parse the configuration file if present" do
            FileTest.stubs(:exists?).with(@path).returns(true)
            @parser = mock 'parser'
            @parser.expects(:parse).returns({})
            Puppet::FileServing::Configuration::Parser.stubs(:new).returns(@parser)
            Puppet::FileServing::Configuration.create
        end

        it "should determine the path to the configuration file from the Puppet settings" do
            Puppet::FileServing::Configuration.create
        end
    end

    describe "when parsing the configuration file" do

        before do
            FileTest.stubs(:exists?).with(@path).returns(true)
            @parser = mock 'parser'
            Puppet::FileServing::Configuration::Parser.stubs(:new).returns(@parser)
        end

        it "should set the mount list to the results of parsing" do
            @parser.expects(:parse).returns("one" => mock("mount"))
            config = Puppet::FileServing::Configuration.create
            config.mounted?("one").should be_true
        end

        it "should not raise exceptions" do
            @parser.expects(:parse).raises(ArgumentError)
            proc { Puppet::FileServing::Configuration.create }.should_not raise_error
        end

        it "should replace the existing mount list with the results of reparsing" do
            @parser.expects(:parse).returns("one" => mock("mount"))
            config = Puppet::FileServing::Configuration.create
            config.mounted?("one").should be_true
            # Now parse again
            @parser.expects(:parse).returns("two" => mock('other'))
            config.send(:readconfig, false)
            config.mounted?("one").should be_false
            config.mounted?("two").should be_true
        end

        it "should not replace the mount list until the file is entirely parsed successfully" do
            @parser.expects(:parse).returns("one" => mock("mount"))
            @parser.expects(:parse).raises(ArgumentError)
            config = Puppet::FileServing::Configuration.create
            # Now parse again, so the exception gets thrown
            config.send(:readconfig, false)
            config.mounted?("one").should be_true
        end

        it "should add modules and plugins mounts even if the file does not exist" do
            FileTest.expects(:exists?).returns false # the file doesn't exist
            config = Puppet::FileServing::Configuration.create
            config.mounted?("modules").should be_true
            config.mounted?("plugins").should be_true
        end

        it "should add modules and plugins mounts even if they are not returned by the parser" do
            @parser.expects(:parse).returns("one" => mock("mount"))
            FileTest.expects(:exists?).returns true # the file doesn't exist
            config = Puppet::FileServing::Configuration.create
            config.mounted?("modules").should be_true
            config.mounted?("plugins").should be_true
        end
    end

    describe "when finding the specified mount" do
        it "should choose the named mount if one exists" do
            config = Puppet::FileServing::Configuration.create
            config.expects(:mounts).returns("one" => "foo")
            config.find_mount("one", "mynode").should == "foo"
        end

        it "should use the environment of the module mount to find a matching module if the named module cannot be found" do
            config = Puppet::FileServing::Configuration.create

            mod = mock 'module'
            env = mock 'environment'
            env.expects(:module).with("foo").returns mod
            mount = mock 'mount'
            mount.expects(:environment).with("mynode").returns env

            config.stubs(:mounts).returns("modules" => mount)
            Puppet::Util::Warnings.expects(:warnonce)
            config.find_mount("foo", "mynode").should equal(mount)
        end

        it "should return nil if there is no such named mount and no module with the same name exists" do
            config = Puppet::FileServing::Configuration.create

            env = mock 'environment'
            env.expects(:module).with("foo").returns nil
            mount = mock 'mount'
            mount.expects(:environment).with("mynode").returns env

            config.stubs(:mounts).returns("modules" => mount)
            config.find_mount("foo", "mynode").should be_nil
        end
    end

    describe "when finding the mount name and relative path in a request key" do
        before do
            @config = Puppet::FileServing::Configuration.create
            @config.stubs(:find_mount)

            @request = stub 'request', :key => "foo/bar/baz", :options => {}
        end

        it "should reread the configuration" do
            @config.expects(:readconfig)

            @config.split_path(@request)
        end

        it "should treat the first field of the URI path as the mount name" do
            @config.expects(:find_mount).with { |name, node| name == "foo" }

            @config.split_path(@request)
        end

        it "should fail if the mount name is not alpha-numeric" do
            @request.expects(:key).returns "foo&bar/asdf"

            lambda { @config.split_path(@request) }.should raise_error(ArgumentError)
        end

        it "should support dashes in the mount name" do
            @request.expects(:key).returns "foo-bar/asdf"

            lambda { @config.split_path(@request) }.should_not raise_error(ArgumentError)
        end

        it "should use the mount name and node to find the mount" do
            @config.expects(:find_mount).with { |name, node| name == "foo" and node == "mynode" }
            @request.options[:node] = "mynode"

            @config.split_path(@request)
        end

        it "should return nil if the mount cannot be found" do
            @config.expects(:find_mount).returns nil

            @config.split_path(@request).should be_nil
        end

        it "should return the mount and the relative path if the mount is found" do
            mount = stub 'mount', :name => "foo"
            @config.expects(:find_mount).returns mount

            @config.split_path(@request).should == [mount, "bar/baz"]
        end

        it "should remove any double slashes" do
            @request.stubs(:key).returns "foo/bar//baz"
            mount = stub 'mount', :name => "foo"
            @config.expects(:find_mount).returns mount

            @config.split_path(@request).should == [mount, "bar/baz"]
        end

        it "should return the relative path as nil if it is an empty string" do
            @request.expects(:key).returns "foo"
            mount = stub 'mount', :name => "foo"
            @config.expects(:find_mount).returns mount

            @config.split_path(@request).should == [mount, nil]
        end

        it "should add 'modules/' to the relative path if the modules mount is used but not specified, for backward compatibility" do
            @request.expects(:key).returns "foo/bar"
            mount = stub 'mount', :name => "modules"
            @config.expects(:find_mount).returns mount

            @config.split_path(@request).should == [mount, "foo/bar"]
        end
    end
end
