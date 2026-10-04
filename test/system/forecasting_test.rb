require "application_system_test_case"

class ForecastingTest < ApplicationSystemTestCase
  setup do
    sign_in @user = users(:family_admin)
  end

  test "can open forecasting from the nav" do
    visit root_path

    within "nav.h-full" do
      click_link "Forecasting"
    end

    assert_current_path forecasting_path
    assert_selector "h1", text: "Forecasting"
  end

  test "forecasting shows projection and can update assumptions" do
    visit forecasting_path

    assert_text "Current net worth"
    assert_text "FI number"
    assert_selector "[data-testid='forecast-chart']"

    fill_in "annual_growth_rate", with: "8"
    fill_in "current_age", with: "35"
    click_button "Update forecast"

    assert_selector "[data-testid='forecast-chart']"
    assert_text "Current net worth"
  end
end
