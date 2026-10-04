require "test_helper"

class NetWorthForecastTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
  end

  def build(net_worth:, monthly_contribution:, annual_growth_rate:, years:, annual_expenses: nil)
    BalanceSheet.any_instance.stubs(:net_worth).returns(net_worth)
    NetWorthForecast.new(
      @family,
      monthly_contribution: monthly_contribution,
      annual_growth_rate: annual_growth_rate,
      years: years,
      annual_expenses: annual_expenses
    )
  end

  test "series starts at current net worth" do
    forecast = build(net_worth: 50_000, monthly_contribution: 0, annual_growth_rate: 0, years: 5)
    assert_equal 50_000.0, forecast.series.first.net_worth
    assert_equal 0, forecast.series.first.year
  end

  test "zero growth accumulates contributions" do
    forecast = build(net_worth: 0, monthly_contribution: 1_000, annual_growth_rate: 0, years: 1)
    assert_in_delta 12_000.0, forecast.ending_net_worth, 0.01
  end

  test "series has one point per year plus today" do
    forecast = build(net_worth: 0, monthly_contribution: 0, annual_growth_rate: 0, years: 10)
    assert_equal 11, forecast.series.size
  end

  test "fi number uses the 4 percent rule" do
    forecast = build(net_worth: 0, monthly_contribution: 0, annual_growth_rate: 0, years: 5, annual_expenses: 40_000)
    assert_equal 1_000_000.0, forecast.fi_number
  end

  test "fi number is nil without annual expenses" do
    forecast = build(net_worth: 0, monthly_contribution: 0, annual_growth_rate: 0, years: 5)
    assert_nil forecast.fi_number
    assert_nil forecast.fi_date
  end

  test "already financially independent reaches fi immediately" do
    forecast = build(net_worth: 2_000_000, monthly_contribution: 0, annual_growth_rate: 0, years: 5, annual_expenses: 40_000)
    assert_equal 0, forecast.months_to_fi
  end

  test "fi not reached within horizon returns nil" do
    forecast = build(net_worth: 0, monthly_contribution: 100, annual_growth_rate: 0, years: 1, annual_expenses: 40_000)
    assert_nil forecast.months_to_fi
    assert_not forecast.fi_reached_within_horizon?
  end

  test "negative net worth does not compound at the growth rate" do
    forecast = build(net_worth: -50_000, monthly_contribution: 0, annual_growth_rate: 6, years: 10)
    # With no contributions, debt should not balloon at the market return rate.
    assert_equal(-50_000.0, forecast.ending_net_worth)
  end

  test "growth compounds net worth above pure contributions" do
    grown = build(net_worth: 10_000, monthly_contribution: 500, annual_growth_rate: 7, years: 10).ending_net_worth
    flat = build(net_worth: 10_000, monthly_contribution: 500, annual_growth_rate: 0, years: 10).ending_net_worth
    assert_operator grown, :>, flat
  end
end
