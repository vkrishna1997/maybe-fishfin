require "test_helper"

class Transactions::CategorySuggestionsControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    sign_in @user = users(:family_admin)
    @family = @user.family
  end

  test "applies suggested categories" do
    category = @family.categories.create!(name: "Coffee", classification: "expense")
    account = @family.accounts.create!(name: "Checking", balance: 0, currency: "USD", accountable: Depository.new)
    entry = create_transaction(account: account, name: "Blue Bottle", amount: 6)
    transaction = entry.transaction

    assert_nil transaction.category

    post transactions_category_suggestions_url, params: {
      suggestions: { transaction.id => category.id }
    }

    assert_redirected_to transactions_url
    assert_equal category, transaction.reload.category
    assert_equal "1 transaction categorized", flash[:notice]
  end

  test "ignores blank category ids" do
    account = @family.accounts.create!(name: "Checking", balance: 0, currency: "USD", accountable: Depository.new)
    entry = create_transaction(account: account, name: "Blue Bottle", amount: 6)
    transaction = entry.transaction

    post transactions_category_suggestions_url, params: {
      suggestions: { transaction.id => "" }
    }

    assert_nil transaction.reload.category
    assert_equal "0 transactions categorized", flash[:notice]
  end
end
