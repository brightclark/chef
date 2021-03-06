# Author:: Prajakta Purohit (<prajakta@chef.io>)
# Author:: Lamont Granquist (<lamont@chef.io>)
#
# Copyright:: Copyright 2011-2020, Chef Software Inc.
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

require_relative "../resource"
require_relative "../digester"

class Chef
  class Resource
    class RegistryKey < Chef::Resource
      unified_mode true

      provides(:registry_key) { true }

      description "Use the registry_key resource to create and delete registry keys in Microsoft Windows."
      introduced "11.0"

      state_attrs :values

      default_action :create
      allowed_actions :create, :create_if_missing, :delete, :delete_key

      # Some registry key data types may not be safely reported as json.
      # Example (CHEF-5323):
      #
      # registry_key 'HKEY_CURRENT_USER\\ChefTest2014' do
      #   values [{
      #     :name => "ValueWithBadData",
      #     :type => :binary,
      #     :data => 255.chr * 1
      #   }]
      #   action :create
      # end
      #
      # will raise Encoding::UndefinedConversionError: "\xFF" from ASCII-8BIT to UTF-8.
      #
      # To avoid sending data that cannot be nicely converted for json, we have
      # the values method return "safe" data if the data type is "unsafe". Known "unsafe"
      # data types are :binary, :dword, :dword-big-endian, and :qword. If other
      # criteria generate data that cannot reliably be sent as json, add that criteria
      # to the needs_checksum? method. When unsafe data is detected, the values method
      # returns an md5 checksum of the listed data.
      #
      # :unscrubbed_values returns the values exactly as provided in the resource (i.e.,
      # data is not checksummed, regardless of the data type/"unsafe" criteria).
      #
      # Future:
      # If we have conflicts with other resources reporting json incompatible state, we
      # may want to extend the state_attrs API with the ability to rename POST'd attrs.
      #
      # See lib/chef/resource_reporter.rb for more information.
      attr_reader :unscrubbed_values

      def initialize(name, run_context = nil)
        super
        @values, @unscrubbed_values = [], []
      end

      property :key, String, name_property: true

      def values(arg = nil)
        if not arg.nil?
          if arg.is_a?(Hash)
            @values = [ Mash.new(arg).symbolize_keys ]
          elsif arg.is_a?(Array)
            @values = []
            arg.each do |value|
              @values << Mash.new(value).symbolize_keys
            end
          else
            raise ArgumentError, "Bad type for RegistryKey resource, use Hash or Array"
          end

          @values.each do |v|
            raise ArgumentError, "Missing name key in RegistryKey values hash" unless v.key?(:name)

            v.each_key do |key|
              raise ArgumentError, "Bad key #{key} in RegistryKey values hash" unless %i{name type data}.include?(key)
            end
            raise ArgumentError, "Type of name => #{v[:name]} should be string" unless v[:name].is_a?(String)

            if v[:type]
              raise ArgumentError, "Type of type => #{v[:type]} should be symbol" unless v[:type].is_a?(Symbol)
            end
          end
          @unscrubbed_values = @values
        elsif instance_variable_defined?(:@values)
          scrub_values(@values)
        end
      end

      property :recursive, [TrueClass, FalseClass], default: false
      property :architecture, Symbol, default: :machine, equal_to: %i{machine x86_64 i386}

      private

      def scrub_values(values)
        scrubbed = []
        values.each do |value|
          scrubbed_value = value.dup
          if needs_checksum?(scrubbed_value)
            data_io = StringIO.new(scrubbed_value[:data].to_s)
            scrubbed_value[:data] = Chef::Digester.instance.generate_checksum(data_io)
          end
          scrubbed << scrubbed_value
        end
        scrubbed
      end

      # Some data types may raise errors when sent as json. Returns true if this
      # value's data may need to be converted to a checksum.
      def needs_checksum?(value)
        unsafe_types = %i{binary dword dword_big_endian qword}
        unsafe_types.include?(value[:type])
      end

    end
  end
end
