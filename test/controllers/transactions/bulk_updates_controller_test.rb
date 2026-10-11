require "test_helper"

class Transactions::BulkUpdatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "bulk update" do
    transactions = @user.family.entries.transactions

    assert_difference [ "Entry.count", "Transaction.count" ], 0 do
      post transactions_bulk_update_url, params: {
        bulk_update: {
          entry_ids: transactions.map(&:id),
          date: 1.day.ago.to_date,
          category_id: Category.second.id,
          merchant_id: Merchant.second.id,
          tag_ids: [ Tag.first.id, Tag.second.id ],
          notes: "Updated note"
        }
      }
    end

    assert_redirected_to transactions_url
    assert_equal "#{transactions.count} transactions updated", flash[:notice]

    transactions.reload.each do |transaction|
      assert_equal 1.day.ago.to_date, transaction.date
      assert_equal Category.second, transaction.transaction.category
      assert_equal Merchant.second, transaction.transaction.merchant
      assert_equal "Updated note", transaction.notes
      assert_equal [ Tag.first.id, Tag.second.id ], transaction.entryable.tag_ids.sort
    end
  end

  test "single-transaction category change sets create-rule cta" do
    entry = @user.family.entries.transactions.first
    new_category = @user.family.categories.where.not(id: entry.transaction.category_id).first

    post transactions_bulk_update_url, params: {
      bulk_update: { entry_ids: [ entry.id ], category_id: new_category.id }
    }

    assert_redirected_to transactions_url
    assert_equal "category_rule", flash[:cta][:type]
    assert_equal new_category.id, flash[:cta][:category_id]
  end

  test "multi-transaction category change does not set create-rule cta" do
    entries = @user.family.entries.transactions.limit(2)

    post transactions_bulk_update_url, params: {
      bulk_update: { entry_ids: entries.map(&:id), category_id: Category.second.id }
    }

    assert_redirected_to transactions_url
    assert_nil flash[:cta]
  end

  test "re-selecting the same category does not set create-rule cta" do
    entry = @user.family.entries.transactions.detect { |e| e.transaction.category_id.present? }

    post transactions_bulk_update_url, params: {
      bulk_update: { entry_ids: [ entry.id ], category_id: entry.transaction.category_id }
    }

    assert_redirected_to transactions_url
    assert_nil flash[:cta]
  end
end
