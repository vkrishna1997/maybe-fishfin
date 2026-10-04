require "application_system_test_case"

class ReportsTest < ApplicationSystemTestCase
  setup do
    sign_in @user = users(:family_admin)
  end

  test "can open reports from sidebar" do
    within "nav.h-full" do
      click_link "Reports"
    end

    assert_current_path reports_path
    assert_selector "h1", text: "Reports"
    assert_selector "h2", text: "Cash Flow"
  end

  test "reports page shows cash flow summary tiles" do
    visit reports_path

    assert_text "Income"
    assert_text "Expenses"
    assert_text "Net Savings"
    assert_text "Savings Rate"
  end

  test "reports page shows category breakdown sections" do
    visit reports_path

    assert_selector "h3", text: /Spending by category/i
    assert_selector "h3", text: /Income by category/i
  end

  test "reports period selector reloads the cash flow section" do
    visit reports_path

    within "#reports_cashflow_section" do
      assert_selector "select"
      select "90D", from: "cashflow_period"
    end

    assert_current_path reports_path, ignore_query: true
    assert_selector "h2", text: "Cash Flow"
  end

  test "dashboard no longer renders the cash flow sankey" do
    visit root_path

    assert_no_selector "[data-controller='sankey-chart']"
  end
end
