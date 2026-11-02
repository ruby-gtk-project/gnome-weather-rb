# frozen_string_literal: true

require 'adwaita'

# AboutDialog is the About window.
#
# Ported from MainWindow#showAbout in upstream's src/app/window.ts: the same
# credits, the same copyright and licence, and the same conditional legal
# section carrying the weather provider's attribution — added only when there
# is a location on screen to take an attribution from.
#
class AboutDialog
  APPLICATION_NAME = 'Weather'
  APPLICATION_ICON = 'weather-few-clouds-symbolic'
  DEVELOPER_NAME = 'The GNOME Project'
  COPYRIGHT = 'Copyright 2013-2015 The Weather Developers'
  WEBSITE = 'https://apps.gnome.org/Weather/'
  ISSUE_URL = 'https://gitlab.gnome.org/GNOME/gnome-weather/-/issues/'

  DEVELOPERS = ['Giovanni Campagna <gcampagna@src.gnome.org>'].freeze

  DESIGNERS = [
    'Jakub Steiner <jimmac@gmail.com>',
    'Pink Sherbet Photography (D. Sharon Pruitt)',
    'Elliott Brown',
    'Analogick',
    'DBduo Photography (Daniel R. Blume)',
    'davharuk',
    'Tech Haven Ministries',
    'Jim Pennucci',
  ].freeze

  def initialize(version:, attribution: nil)
    @version = version
    @attribution = attribution
  end

  def build
    dialog.tap do |about|
      if @attribution
        about.add_legal_section(
          APPLICATION_NAME,
          nil,
          Gtk::License::CUSTOM,
          @attribution,
        )
      end
    end
  end

  def present(parent)
    build.present(parent)
  end

  def dialog
    @dialog ||= Adwaita::AboutDialog.new.tap do |about|
      about.application_name = APPLICATION_NAME
      about.application_icon = APPLICATION_ICON
      about.developer_name = DEVELOPER_NAME
      about.developers = DEVELOPERS
      about.designers = DESIGNERS
      about.translator_credits = 'translator-credits'
      about.copyright = COPYRIGHT
      about.license_type = Gtk::License::GPL_2_0
      about.version = @version
      about.website = WEBSITE
      about.issue_url = ISSUE_URL
    end
  end
end
