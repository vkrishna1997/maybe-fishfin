require "application_system_test_case"

class GoalsTest < ApplicationSystemTestCase
  setup do
    sign_in @user = users(:family_admin)
  end

  test "can open goals from the nav" do
    visit root_path

    within "nav.h-full" do
      click_link "Goals"
    end

    assert_current_path goals_path
    assert_selector "h1", text: "Goals"
  end

  test "can create a goal and see its progress" do
    visit goals_path

    click_link "New goal"

    within "#modal" do
      fill_in "goal[name]", with: "Emergency fund"
      fill_in "goal[target_amount]", with: "10000"
      fill_in "goal[current_amount]", with: "2500"
      click_button "Create Goal"
    end

    assert_text "Emergency fund"
    assert_text "25%"
    assert_selector "[data-testid='goals-list']"
  end

  test "existing goal renders in the list" do
    @user.family.goals.create!(name: "Vacation", target_amount: 4000, current_amount: 1000, currency: "USD")

    visit goals_path

    assert_text "Vacation"
    assert_text "Total saved"
  end
end
