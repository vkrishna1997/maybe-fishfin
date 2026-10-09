require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    sign_in @user = users(:family_admin)
  end

  test "dashboard" do
    get root_path
    assert_response :ok
  end

  test "dashboard no longer renders the cashflow sankey" do
    get root_path
    assert_response :ok
    assert_select "#cashflow-sankey-chart", count: 0
  end

  test "reports" do
    get reports_path
    assert_response :ok
    assert_select "h1", text: "Reports"
    assert_select "button", text: "Cash Flow"
    assert_select "button", text: "Spending"
    assert_select "button", text: "Income"
  end

  test "reports shows cash flow summary tiles" do
    get reports_path
    assert_response :ok
    assert_select "p", text: "Income"
    assert_select "p", text: "Expenses"
    assert_select "p", text: "Net Savings"
    assert_select "p", text: "Savings Rate"
  end

  test "reports shows spending and income donut tabs" do
    get reports_path
    assert_response :ok
    assert_select "h2", text: "Spending"
    assert_select "h2", text: "Income"
    assert_select "[data-controller='donut-chart']", minimum: 1
  end

  test "reports sankey defaults to the income classification" do
    get reports_path
    assert_response :ok
    assert_select "[data-sankey-chart-default-classification-value='income']"
  end

  test "reports shows a period-over-period comparison label" do
    get reports_path(cashflow_period: "last_30_days")
    assert_response :ok
    assert_select "p", text: /vs\. last month/
  end

  test "reports accepts a valid cashflow period" do
    get reports_path(cashflow_period: "last_90_days")
    assert_response :ok
  end

  test "reports falls back to default on an invalid cashflow period" do
    get reports_path(cashflow_period: "not_a_real_period")
    assert_response :ok
  end

  test "reports sankey is interactive and renders a drill-down frame" do
    get reports_path
    assert_response :ok
    assert_select "turbo-frame#reports_transactions"
    assert_select "[data-sankey-chart-transactions-url-value]"
  end

  test "report transactions drill-down renders for a category" do
    get report_transactions_path(category: "Food & Drink", cashflow_period: "last_30_days")
    assert_response :ok
    assert_select "turbo-frame#reports_transactions"
    assert_select "[data-testid='report-transactions']"
    assert_select "h3", text: "Food & Drink"
  end

  test "report transactions drill-down handles an invalid period" do
    get report_transactions_path(category: "Food & Drink", cashflow_period: "not_a_real_period")
    assert_response :ok
    assert_select "[data-testid='report-transactions']"
  end

  test "report transactions classification drill-down shows all income" do
    get report_transactions_path(classification: "income", cashflow_period: "last_30_days")
    assert_response :ok
    assert_select "[data-testid='report-transactions']"
    assert_select "h3", text: "All income"
  end

  test "report transactions classification drill-down shows all spending" do
    get report_transactions_path(classification: "expense", cashflow_period: "last_30_days")
    assert_response :ok
    assert_select "h3", text: "All spending"
  end

  test "category drill-down includes subcategory transactions" do
    parent = categories(:food_and_drink)
    child = categories(:subcategory)

    create_transaction(name: "Parent lunch", amount: 20, date: Date.current, category: parent)
    create_transaction(name: "Child dinner", amount: 30, date: Date.current, category: child)

    get report_transactions_path(category: parent.name, cashflow_period: "last_30_days")
    assert_response :ok
    assert_select "p", text: "Parent lunch"
    assert_select "p", text: "Child dinner"
  end

  test "cashflow" do
    get cashflow_path
    assert_response :ok
    assert_select "h1", text: "Cash Flow"
  end

  test "cashflow shows the income vs expenses over-time chart" do
    get cashflow_path
    assert_response :ok
    assert_select "[data-testid='cashflow-over-time-chart']"
    assert_select "h2", text: "Income vs. expenses"
  end

  test "cashflow shows cash flow summary tiles" do
    get cashflow_path
    assert_response :ok
    assert_select "p", text: "Income"
    assert_select "p", text: "Expenses"
    assert_select "p", text: "Net Savings"
    assert_select "p", text: "Savings Rate"
  end

  test "cashflow accepts a valid cashflow period" do
    get cashflow_path(cashflow_period: "last_90_days")
    assert_response :ok
  end

  test "cashflow falls back to default on an invalid cashflow period" do
    get cashflow_path(cashflow_period: "not_a_real_period")
    assert_response :ok
  end

  test "investments" do
    get investments_path
    assert_response :ok
    assert_select "h1", text: "Investments"
  end

  test "investments shows portfolio summary tiles" do
    get investments_path
    assert_response :ok
    assert_select "p", text: "Total value"
    assert_select "p", text: "Holdings"
    assert_select "p", text: "Cash"
    assert_select "p", text: "Total return"
  end

  test "investments shows allocation and holdings sections" do
    get investments_path
    assert_response :ok
    assert_select "h2", text: "Allocation"
    assert_select "h2", text: "Holdings"
    assert_select "h2", text: "Accounts"
  end

  test "recurring" do
    get recurring_path
    assert_response :ok
    assert_select "h1", text: "Recurring"
  end

  test "recurring detects a monthly subscription" do
    merchant = @user.family.merchants.create!(name: "Spotify", type: "FamilyMerchant")
    5.times do |i|
      create_transaction(
        account: accounts(:depository),
        name: "Spotify",
        amount: 11.99,
        date: (i * 30).days.ago.to_date,
        merchant: merchant
      )
    end

    get recurring_path
    assert_response :ok
    assert_select "[data-testid='recurring-expenses-table']"
    assert_select "td", text: "Spotify"
  end

  test "forecasting" do
    get forecasting_path
    assert_response :ok
    assert_select "h1", text: "Forecasting"
    assert_select "[data-testid='forecast-summary']"
  end

  test "forecasting respects custom assumptions" do
    get forecasting_path(monthly_contribution: 2000, annual_growth_rate: 5, current_age: 40, annual_expenses: 48000)
    assert_response :ok
    assert_select "[data-testid='forecast-chart']"
    assert_select "[data-testid='forecast-summary']"
  end

  test "forecasting renders through the shared time-series chart" do
    get forecasting_path(monthly_contribution: 2000, annual_growth_rate: 5, current_age: 40, annual_expenses: 48000)
    assert_response :ok
    assert_select "[data-testid='forecast-chart'][data-controller='time-series-chart']"
    assert_select "[data-time-series-chart-data-value]"
    assert_select "[data-time-series-chart-reference-line-value]"
    assert_select "[data-time-series-chart-highlight-point-value]"
  end

  test "changelog" do
    VCR.use_cassette("git_repository_provider/fetch_latest_release_notes") do
      get changelog_path
      assert_response :ok
    end
  end

  test "changelog with nil release notes" do
    # Mock the GitHub provider to return nil (simulating API failure or no releases)
    github_provider = mock
    github_provider.expects(:fetch_latest_release_notes).returns(nil)
    Provider::Registry.stubs(:get_provider).with(:github).returns(github_provider)

    get changelog_path
    assert_response :ok
    assert_select "h2", text: "Release notes unavailable"
    assert_select "a[href='https://github.com/maybe-finance/maybe/releases']"
  end

  test "changelog with incomplete release notes" do
    # Mock the GitHub provider to return incomplete data (missing some fields)
    github_provider = mock
    incomplete_data = {
      avatar: nil,
      username: "maybe-finance",
      name: "Test Release",
      published_at: nil,
      body: nil
    }
    github_provider.expects(:fetch_latest_release_notes).returns(incomplete_data)
    Provider::Registry.stubs(:get_provider).with(:github).returns(github_provider)

    get changelog_path
    assert_response :ok
    assert_select "h2", text: "Test Release"
    # Should not crash even with nil values
  end
end
