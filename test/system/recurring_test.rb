require "application_system_test_case"

class RecurringTest < ApplicationSystemTestCase
  include EntriesTestHelper

  setup do
    sign_in @user = users(:family_admin)
  end

  test "can open recurring from the nav" do
    visit root_path

    within "nav.h-full" do
      click_link "Recurring"
    end

    assert_current_path recurring_path
    assert_selector "h1", text: "Recurring"
  end

  test "recurring page lists a detected subscription" do
    merchant = @user.family.merchants.create!(name: "RecurTest Streamflix", type: "FamilyMerchant")
    5.times do |i|
      create_transaction(
        account: accounts(:depository),
        name: "RecurTest Streamflix",
        amount: 15.99,
        date: (i * 30).days.ago.to_date,
        merchant: merchant
      )
    end

    visit recurring_path

    assert_text "Est. monthly recurring"
    assert_selector "[data-testid='recurring-expenses-table']"
    assert_text "RecurTest Streamflix"
    assert_text "Monthly"
  end
end
