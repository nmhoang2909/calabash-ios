module Calabash
  module Cucumber

    # Collection of methods for interacting with the keyboard.
    #
    # We've gone to great lengths to provide the fastest keyboard entry possible.
    module KeyboardHelpers

      # This module is expected to be included in Calabash::Cucumber::Core.
      # Core includes necessary methods from:
      #
      # StatusBarHelpers
      # EnvironmentHelpers
      # WaitHelpers
      # FailureHelpers
      # UIA

      require "calabash-cucumber/map"

      # Returns true if a docked keyboard is visible.
      #
      # A docked keyboard is pinned to the bottom of the view.
      #
      # Keyboards on the iPhone and iPod are docked.
      #
      # @return [Boolean] if a keyboard is visible and docked.
      def docked_keyboard_visible?
        keyboard = _query_for_keyboard

        return false if keyboard.nil?

        return true if device_family_iphone?

        keyboard_height = keyboard['rect']['height']
        keyboard_y = keyboard['rect']['y']
        dimensions = screen_dimensions
        scale = dimensions[:scale]

        if landscape?
          screen_height = dimensions[:width]/scale
        else
          screen_height = dimensions[:height]/scale
        end

        screen_height - keyboard_height == keyboard_y
      end

      # Returns true if an undocked keyboard is visible.
      #
      # A undocked keyboard is floats in the middle of the view.
      #
      # @return [Boolean] Returns false if the device is not an iPad; all
      # keyboards on the iPhone and iPod are docked.
      def undocked_keyboard_visible?
        return false if device_family_iphone?

        keyboard = _query_for_keyboard
        return false if keyboard.nil?

        !docked_keyboard_visible?
      end

      # Returns true if a split keyboard is visible.
      #
      # A split keyboard is floats in the middle of the view and is split to
      # allow faster thumb typing
      #
      # @return [Boolean] Returns false if the device is not an iPad; all
      # keyboards on the Phone and iPod are docked and not split.
      def split_keyboard_visible?
        return false if device_family_iphone?
        _query_for_split_keyboard && !_query_for_keyboard
      end

      # Returns true if there is a visible keyboard.
      #
      # @return [Boolean] Returns true if there is a visible keyboard.
      def keyboard_visible?
        # Order matters!
        docked_keyboard_visible? ||
          undocked_keyboard_visible? ||
          split_keyboard_visible?
      end

      # @!visibility private
      # Raises an error ir the keyboard is not visible.
      def expect_keyboard_visible!
        if !keyboard_visible?
          screenshot_and_raise "Keyboard is not visible"
        end
        true
      end

      # Waits for a keyboard to appear and once it does appear waits for
      # `:post_timeout` seconds.
      #
      # @see Calabash::Cucumber::WaitHelpers#wait_for for other options this
      #  method can handle.
      #
      # @param [Hash] options controls the `wait_for` behavior
      # @option opts [String] :timeout_message ('keyboard did not appear')
      #  Controls the message that appears in the error.
      # @option opts [Number] :post_timeout (0.3) Controls how long to wait
      #  _after_ the keyboard has appeared.
      #
      # @raise [Calabash::Cucumber::WaitHelpers::WaitError] if no keyboard appears
      def wait_for_keyboard(options={})
        default_opts = {
          :timeout_message => "Keyboard did not appear",
          :post_timeout => 0.3
        }

        merged_opts = default_opts.merge(options)
        wait_for(merged_opts) do
          keyboard_visible?
        end
        true
      end

      # Waits for a keyboard to disappear.
      #
      # @see Calabash::Cucumber::WaitHelpers#wait_for for other options this
      #  method can handle.
      #
      # @param [Hash] options controls the `wait_for` behavior
      # @option opts [String] :timeout_message ('keyboard did not appear')
      #  Controls the message that appears in the error.
      #
      # @raise [Calabash::Cucumber::WaitHelpers::WaitError] If keyboard does
      #  not disappear.
      def wait_for_no_keyboard(options={})
        default_opts = {
          :timeout_message => "Keyboard is visible",
        }

        merged_opts = default_opts.merge(options)
        wait_for(merged_opts) do
          !keyboard_visible?
        end
        true
      end

      # Used for detecting keyboards that are not normally visible to calabash;
      # e.g. the keyboard on the `MFMailComposeViewController`
      #
      # @note
      #  IMPORTANT this should only be used when the app does not respond to
      #  `keyboard_visible?` and UIAutomation is being used.
      #
      # @see #keyboard_visible?
      #
      # @raise [RuntimeError] If the app was not launched with instruments
      def uia_keyboard_visible?
        if !uia_available?
          raise RuntimeError, %Q[
This method requires UIAutomation and your application was not launched with
instruments.  UIAutomation is not available for iOS 10 or for Xcode 8.

Use `uia_available?` in your tests to branch on UIAutomation availability.

]
        end
        res = uia_query_windows(:keyboard)
        res != ":nil"
      end

      # Waits for a keyboard that is not normally visible to calabash;
      # e.g. the keyboard on `MFMailComposeViewController`.
      #
      # @note
      #  IMPORTANT this should only be used when the app does not respond to
      #  `keyboard_visible?` and UIAutomation is being used.
      #
      # @see #keyboard_visible?
      #
      # @raise [RuntimeError] if the app was not launched with instruments
      def uia_wait_for_keyboard(options={})
        if !uia_available?
          raise RuntimeError, %Q[
This method requires UIAutomation and your application was not launched with
instruments.  UIAutomation is not available for iOS 10 or for Xcode 8.

Use `uia_available?` in your tests to branch on UIAutomation availability.

]
        end

        default_opts = {
          :timeout => 10,
          :retry_frequency => 0.1,
          :post_timeout => 0.5,
          :timeout_message => "Keyboard did not appear"
        }

        options = default_opts.merge(options)

        wait_for(options) do
          uia_keyboard_visible?
        end
        true
      end

      # Waits for a keyboard to appear and returns the localized name of the
      # `key_code` signifier
      #
      # @param [String] key_code Maps to a specific name in some localization
      def lookup_key_name(key_code)
        wait_for_keyboard
        begin
          response_json = JSON.parse(http(:path => 'keyboard-language'))
        rescue JSON::ParserError
          raise RuntimeError, "Could not parse output of keyboard-language route. Did the app crash?"
        end
        if response_json['outcome'] != 'SUCCESS'
          screenshot_and_raise "failed to retrieve the keyboard localization"
        end
        localized_lang = response_json['results']['input_mode']
        RunLoop::L10N.new.lookup_localization_name(key_code, localized_lang)
      end

      # @!visibility private
      # Returns the the text in the first responder.
      #
      # The first responder will be the UITextField or UITextView instance
      # that is associated with the visible keyboard.
      #
      # Returns empty string if no textField or textView elements are found to be
      # the first responder.
      #
      # @raise [RuntimeError] if there is no visible keyboard
      def text_from_first_responder
        if !keyboard_visible?
          screenshot_and_raise "There must be a visible keyboard"
        end

        ['textField', 'textView'].each do |ui_class|
          query = "#{ui_class} isFirstResponder:1"
          result = _query_wrapper(query, :text)
          if !result.empty?
            return result.first
          end
        end
        ""
      end

      # @visibility private
      # TODO Remove in 0.21.0
      alias_method :_text_from_first_responder, :text_from_first_responder

      private

      # @!visibility private
      KEYBOARD_QUERY = "view:'UIKBKeyplaneView'"

      # @!visibility private
      SPLIT_KEYBOARD_QUERY = "view:'UIKBKeyView'"

      # @!visibility private
      def _query_wrapper(query, *args)
        Calabash::Cucumber::Map.map(query, :query, *args)
      end

      # @!visibility private
      def _query_for_keyboard
        _query_wrapper(KEYBOARD_QUERY).first
      end

      # @!visibility private
      def _query_for_split_keyboard
        _query_wrapper(SPLIT_KEYBOARD_QUERY).first
      end
    end
  end
end
