require "application_system_test_case"

class InvestmentsTest < ApplicationSystemTestCase
  setup do
    sign_in @user = users(:family_admin)
  end

  test "can open investments from the nav" do
    visit root_path

    within "nav.h-full" do
      click_link "Investments"
    end

    assert_current_path investments_path
    assert_selector "h1", text: "Investments"
  end

  test "investments page shows portfolio summary and sections" do
    visit investments_path

    assert_text "Total value"
    assert_text "Holdings"
    assert_text "Cash"
    assert_text "Total return"
    assert_selector "h2", text: "Allocation"
    assert_selector "h2", text: "Accounts"
  end
end
