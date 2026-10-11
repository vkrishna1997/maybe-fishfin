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

  test "flags a recurring expense whose latest amount changed" do
    merchant = @family.merchants.create!(name: "PriceHike Gym", type: "FamilyMerchant")
    category = @family.categories.create!(name: "Fitness", classification: "expense")
    # Four stable $30 charges, then a $60 charge most recently.
    [ 30, 30, 30, 30 ].each_with_index do |amt, i|
      create_transaction(account: @account, name: "PriceHike Gym", amount: amt, date: ((i + 1) * 30).days.ago.to_date, merchant: merchant, category: category)
    end
    create_transaction(account: @account, name: "PriceHike Gym", amount: 60, date: Date.current, merchant: merchant, category: category)

    flagged = RecurringSeries.new(@family).flagged
    item = flagged.find { |s| s.name == "PriceHike Gym" }

    assert item, "expected the price-changed series to be flagged"
    assert item.review_reasons.any? { |r| r.include?("Amount up") }
  end

  test "flags an uncategorized recurring series" do
    merchant = @family.merchants.create!(name: "Mystery Sub", type: "FamilyMerchant")
    5.times do |i|
      create_transaction(account: @account, name: "Mystery Sub", amount: 9.99, date: (i * 30).days.ago.to_date, merchant: merchant)
    end

    item = RecurringSeries.new(@family).flagged.find { |s| s.name == "Mystery Sub" }

    assert item, "expected the uncategorized series to be flagged"
    assert_includes item.review_reasons, "No category assigned"
  end

  test "does not flag a healthy categorized series with a recent charge" do
    merchant = @family.merchants.create!(name: "Healthy Sub", type: "FamilyMerchant")
    category = @family.categories.create!(name: "Subs", classification: "expense")
    5.times do |i|
      create_transaction(account: @account, name: "Healthy Sub", amount: 12, date: (i * 30).days.ago.to_date, merchant: merchant, category: category)
    end

    item = RecurringSeries.new(@family).series.find { |s| s.name == "Healthy Sub" }

    assert item
    assert_empty item.review_reasons
  end

  test "exposes entry ids, merchant and category for flagged items" do
    merchant = @family.merchants.create!(name: "Mystery Sub", type: "FamilyMerchant")
    entries = 5.times.map do |i|
      create_transaction(account: @account, name: "Mystery Sub", amount: 9.99, date: (i * 30).days.ago.to_date, merchant: merchant)
    end

    item = RecurringSeries.new(@family).flagged.find { |s| s.name == "Mystery Sub" }

    assert item, "expected the uncategorized series to be flagged"
    assert_equal entries.map(&:id).sort, item.entry_ids.sort
    assert_equal merchant.id, item.merchant_id
    assert_nil item.category_id
    assert_equal({ q: { merchants: [ "Mystery Sub" ] } }, item.review_filter_params)
  end
end
