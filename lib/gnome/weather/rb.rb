require_relative "rb/version"

# frozen_string_literal: true

# The gem's version constant lives under this file, which is why
# spec/spec_helper.rb requires it — the display-free half of the gem's
# namespace, loadable anywhere with no GTK and no display. The app itself is
# required separately (lib/main.rb and friends), which does need a display.
