require "application_system_test_case"

class CashflowTest < ApplicationSystemTestCase
  setup do
    sign_in @user = users(:family_admin)
  end

  test "can open cash flow from the nav" do
    visit root_path

    within "nav.h-full" do
      click_link "Cash Flow"
    end

    assert_current_path cashflow_path
    assert_selector "h1", text: "Cash Flow"
  end

  test "cash flow page shows summary tiles and over-time chart" do
    visit cashflow_path

    assert_text "Income"
    assert_text "Expenses"
    assert_text "Net Savings"
    assert_text "Savings Rate"
    assert_selector "h2", text: "Income vs. expenses"
    assert_selector "[data-testid='cashflow-over-time-chart']"
  end

  test "cash flow period selector reloads the section" do
    visit cashflow_path

    within "#cashflow_section" do
      assert_selector "select"
      select "90D", from: "cashflow_period"
    end

    assert_current_path cashflow_path, ignore_query: true
    assert_selector "h1", text: "Cash Flow"
  end
end
