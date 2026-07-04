# frozen_string_literal: true

require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "about page renders the story and physics model" do
    get about_path
    assert_response :success

    assert_select "h1", "Gravikon"
    assert_select "h3", /Příběh/
    assert_select "h3", /Fyzikální model/
    assert_select ".formula-display", 2
    assert_select "a[href=?]", "/Gravikon.pdf"
    assert_select "a[href=?]", galaxy_index_path
  end

  test "galaxy landing page links to the about page" do
    get galaxy_index_path
    assert_response :success
    assert_select ".galaxy-intro a[href=?]", about_path
  end
end
