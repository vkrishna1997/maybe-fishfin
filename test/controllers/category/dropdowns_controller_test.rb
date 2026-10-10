require "test_helper"

class Category::DropdownsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    @entry = entries(:transaction)
    @category = categories(:food_and_drink)
  end

  test "transaction context targets the transaction and offers a new category link" do
    get category_dropdown_path(transaction_id: @entry.entryable_id, category_id: @category.id)

    assert_response :success
    assert_select "a[href='#{new_category_path}'][data-turbo-frame='modal']"
    assert_select "form[action='#{transaction_category_path(@entry)}']"
  end

  test "bulk context targets the bulk update endpoint for the given entries" do
    get category_dropdown_path(entry_ids: [ @entry.id ])

    assert_response :success
    assert_select "a[href='#{new_category_path}'][data-turbo-frame='modal']"
    assert_select "form[action='#{transactions_bulk_update_path}']"
    assert_select "input[name='bulk_update[entry_ids][]'][value='#{@entry.id}']"
  end
end
