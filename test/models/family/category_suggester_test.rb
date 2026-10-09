require "test_helper"

class Family::CategorySuggesterTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @account = @family.accounts.create!(name: "Checking", balance: 0, currency: "USD", accountable: Depository.new)
  end

  test "suggests category based on merchant history" do
    merchant = @family.merchants.create!(name: "Netflix")
    category = @family.categories.create!(name: "Subscriptions", classification: "expense")

    create_transaction(account: @account, merchant: merchant, category: category, name: "Netflix", amount: 15)
    uncategorized = create_transaction(account: @account, merchant: merchant, name: "Netflix", amount: 16)

    suggestions = Family::CategorySuggester.new(@family).suggestions
    match = suggestions.find { |s| s[:transaction] == uncategorized.transaction }

    assert match, "expected a suggestion for the uncategorized Netflix transaction"
    assert_equal category, match[:category]
  end

  test "suggests category based on description when no merchant" do
    category = @family.categories.create!(name: "Coffee", classification: "expense")

    create_transaction(account: @account, category: category, name: "Blue Bottle", amount: 5)
    uncategorized = create_transaction(account: @account, name: "blue bottle", amount: 6)

    suggestions = Family::CategorySuggester.new(@family).suggestions
    match = suggestions.find { |s| s[:transaction] == uncategorized.transaction }

    assert match, "expected a suggestion from matching description"
    assert_equal category, match[:category]
  end

  test "does not suggest a category of the wrong classification" do
    income_category = @family.categories.create!(name: "Salary", classification: "income")
    merchant = @family.merchants.create!(name: "Acme")

    create_transaction(account: @account, merchant: merchant, category: income_category, name: "Acme", amount: -1000)
    uncategorized = create_transaction(account: @account, merchant: merchant, name: "Acme", amount: 50)

    suggestions = Family::CategorySuggester.new(@family).suggestions
    match = suggestions.find { |s| s[:transaction] == uncategorized.transaction }

    assert_nil match, "should not suggest an income category for an expense transaction"
  end

  test "returns nothing when there is no history" do
    create_transaction(account: @account, name: "Mystery Vendor", amount: 20)

    assert_empty Family::CategorySuggester.new(@family).suggestions
  end
end
