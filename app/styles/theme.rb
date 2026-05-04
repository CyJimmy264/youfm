# frozen_string_literal: true

module YouFM
  module Styles
    class Theme
      THEMES = {
        'dark' => <<~QSS,
          QWidget#main_window {
            background: #111318;
            color: #f4f6f8;
          }

          QLabel#hero_title {
            font-size: 24px;
            font-weight: 700;
            color: #fafbff;
          }

          QLabel#hero_subtitle,
          QLabel#section_label,
          QLabel#status_label,
          QLabel#device_label,
          QLabel#now_playing_label,
          QLabel#recommendation_seed_label {
            color: #b4bdc7;
          }

          QLineEdit#search_input {
            background: #1b1f27;
            border: 1px solid #2b3340;
            border-radius: 10px;
            padding: 10px 12px;
            color: #f4f6f8;
          }

          QPushButton {
            background: #273043;
            color: #f7fbff;
            border: none;
            border-radius: 10px;
            padding: 10px 16px;
          }

          QPushButton#primary_button {
            background: #1db954;
            color: #08110b;
            font-weight: 700;
          }

          QPushButton#ghost_button {
            background: #1b1f27;
            border: 1px solid #2b3340;
          }

          QScrollBar:vertical,
          QScrollBar:horizontal {
            background: transparent;
            border: none;
            margin: 0;
          }

          QScrollBar:vertical {
            width: 10px;
          }

          QScrollBar::handle:vertical {
            background: #465062;
            min-height: 24px;
            border-radius: 5px;
          }

          QScrollBar::handle:vertical:hover {
            background: #586478;
          }

          QScrollBar::add-line:vertical,
          QScrollBar::sub-line:vertical,
          QScrollBar::add-page:vertical,
          QScrollBar::sub-page:vertical {
            background: transparent;
            border: none;
          }

          QScrollBar:horizontal {
            height: 10px;
          }

          QScrollBar::handle:horizontal {
            background: #465062;
            min-width: 24px;
            border-radius: 5px;
          }

          QScrollBar::handle:horizontal:hover {
            background: #586478;
          }

          QScrollBar::add-line:horizontal,
          QScrollBar::sub-line:horizontal,
          QScrollBar::add-page:horizontal,
          QScrollBar::sub-page:horizontal {
            background: transparent;
            border: none;
          }

          QListWidget#results_list {
            background: #151922;
            border: 1px solid #232a36;
            border-radius: 14px;
            padding: 8px;
            outline: none;
          }

          QComboBox#device_picker {
            background: #151922;
            border: 1px solid #232a36;
            border-radius: 10px;
            padding: 8px 10px;
          }

          QListWidget#results_list::item {
            padding: 10px;
            border-radius: 8px;
            color: #f4f6f8;
          }

          QListWidget#results_list::item:selected {
            background: #273043;
            color: #f7fbff;
          }
        QSS
        'light' => <<~QSS
          QWidget#main_window {
            background: #f7f3ea;
            color: #1a202a;
          }

          QLabel#hero_title {
            font-size: 24px;
            font-weight: 700;
            color: #111111;
          }

          QLabel#hero_subtitle,
          QLabel#section_label,
          QLabel#status_label,
          QLabel#device_label,
          QLabel#now_playing_label,
          QLabel#recommendation_seed_label {
            color: #4d5561;
          }

          QLineEdit#search_input {
            background: #fffdf8;
            border: 1px solid #d4c9b7;
            border-radius: 10px;
            padding: 10px 12px;
            color: #1a202a;
          }

          QPushButton {
            background: #d7c3a5;
            color: #1a202a;
            border: none;
            border-radius: 10px;
            padding: 10px 16px;
          }

          QPushButton#primary_button {
            background: #1db954;
            color: #08110b;
            font-weight: 700;
          }

          QPushButton#ghost_button {
            background: #fffdf8;
            border: 1px solid #d4c9b7;
          }

          QScrollBar:vertical,
          QScrollBar:horizontal {
            background: transparent;
            border: none;
            margin: 0;
          }

          QScrollBar:vertical {
            width: 10px;
          }

          QScrollBar::handle:vertical {
            background: #b8a68a;
            min-height: 24px;
            border-radius: 5px;
          }

          QScrollBar::handle:vertical:hover {
            background: #a89272;
          }

          QScrollBar::add-line:vertical,
          QScrollBar::sub-line:vertical,
          QScrollBar::add-page:vertical,
          QScrollBar::sub-page:vertical {
            background: transparent;
            border: none;
          }

          QScrollBar:horizontal {
            height: 10px;
          }

          QScrollBar::handle:horizontal {
            background: #b8a68a;
            min-width: 24px;
            border-radius: 5px;
          }

          QScrollBar::handle:horizontal:hover {
            background: #a89272;
          }

          QScrollBar::add-line:horizontal,
          QScrollBar::sub-line:horizontal,
          QScrollBar::add-page:horizontal,
          QScrollBar::sub-page:horizontal {
            background: transparent;
            border: none;
          }

          QListWidget#results_list {
            background: #fffdf8;
            border: 1px solid #d4c9b7;
            border-radius: 14px;
            padding: 8px;
            outline: none;
          }

          QComboBox#device_picker {
            background: #fffdf8;
            border: 1px solid #d4c9b7;
            border-radius: 10px;
            padding: 8px 10px;
          }

          QListWidget#results_list::item {
            padding: 10px;
            border-radius: 8px;
            color: #1a202a;
          }

          QListWidget#results_list::item:selected {
            background: #ece1d2;
            color: #1a202a;
          }
        QSS
      }.freeze

      attr_reader :name

      def initialize(name:)
        @name = THEMES.key?(name) ? name : 'dark'
      end

      def application_stylesheet
        THEMES.fetch(name)
      end
    end
  end
end
