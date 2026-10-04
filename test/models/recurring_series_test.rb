require "test_helper"

class RecurringSeriesTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @account = accounts(:depository)
  end

  test "detects a monthly recurring expense" do
    merchant = @family.merchants.create!(name: "RecurTest Streamflix", type: "FamilyMerchant")
    5.times do |i|
      create_transaction(
        account: @account,
        name: "RecurTest Streamflix",
        amount: 15.99,
        date: (i * 30).days.ago.to_date,
        merchant: merchant
      )
    end

    series = RecurringSeries.new(@family).expenses
    assert_equal 1, series.size

    netflix = series.first
    assert_equal "RecurTest Streamflix", netflix.name
    assert_equal "Monthly", netflix.cadence
    assert_equal "expense", netflix.classification
    assert_equal 15.99, netflix.amount
    assert_operator netflix.next_date, :>, Date.current
  end

  test "detects recurring income from negative amounts" do
    merchant = @family.merchants.create!(name: "ACME Payroll", type: "FamilyMerchant")
    4.times do |i|
      create_transaction(
        account: @account,
        name: "Paycheck",
        amount: -2500,
        date: (i * 14).days.ago.to_date,
        merchant: merchant
      )
    end

    incomes = RecurringSeries.new(@family).incomes
    assert_equal 1, incomes.size
    assert_equal "Biweekly", incomes.first.cadence
    assert_equal 2500, incomes.first.amount
  end

  test "ignores one-off and irregular transactions" do
    create_transaction(account: @account, name: "Random Shop", amount: 42, date: Date.current)
    create_transaction(account: @account, name: "Another Shop", amount: 9, date: 3.days.ago.to_date)

    assert_empty RecurringSeries.new(@family).series
  end

  test "requires a minimum number of occurrences" do
    merchant = @family.merchants.create!(name: "Gym", type: "FamilyMerchant")
    2.times do |i|
      create_transaction(account: @account, name: "Gym", amount: 30, date: (i * 30).days.ago.to_date, merchant: merchant)
    end

    assert_empty RecurringSeries.new(@family).series
  end

  test "monthly expense estimate normalizes cadence" do
    merchant = @family.merchants.create!(name: "Weekly Co", type: "FamilyMerchant")
    6.times do |i|
      create_transaction(account: @account, name: "Weekly Co", amount: 10, date: (i * 7).days.ago.to_date, merchant: merchant)
    end

    estimate = RecurringSeries.new(@family).monthly_expense_estimate
    assert_in_delta 42.86, estimate.amount.to_f, 0.5
  end
end
