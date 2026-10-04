require "test_helper"

class GoalsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "should get index" do
    get goals_url
    assert_response :success
    assert_select "h1", text: "Goals"
  end

  test "should get new" do
    get new_goal_url
    assert_response :success
  end

  test "should create goal" do
    assert_difference("Goal.count") do
      post goals_url, params: { goal: { name: "Emergency fund", target_amount: 5000, current_amount: 1000 } }
    end

    assert_redirected_to goals_url
    assert_equal "Goal created", flash[:notice]
    assert_equal @user.family.currency, Goal.order(:created_at).last.currency
  end

  test "should not create invalid goal" do
    assert_no_difference("Goal.count") do
      post goals_url, params: { goal: { name: "", target_amount: 0 } }
    end

    assert_redirected_to goals_url
    assert flash[:alert].present?
  end

  test "should get edit" do
    goal = @user.family.goals.create!(name: "Car", target_amount: 20000, currency: "USD")
    get edit_goal_url(goal)
    assert_response :success
  end

  test "should update goal" do
    goal = @user.family.goals.create!(name: "Car", target_amount: 20000, currency: "USD")
    patch goal_url(goal), params: { goal: { current_amount: 2500 } }

    assert_redirected_to goals_url
    assert_equal "Goal updated", flash[:notice]
    assert_equal 2500, goal.reload.current_amount
  end

  test "should destroy goal" do
    goal = @user.family.goals.create!(name: "Car", target_amount: 20000, currency: "USD")
    assert_difference("Goal.count", -1) do
      delete goal_url(goal)
    end

    assert_redirected_to goals_url
  end

  test "cannot access another family's goal" do
    other = families(:empty).goals.create!(name: "Other", target_amount: 100, currency: "USD")
    get edit_goal_url(other)
    assert_response :not_found
  end

  test "index renders savings-pace signal used by the on-track badge" do
    @user.family.goals.create!(name: "Trip", target_amount: 5000, current_amount: 1000, currency: "USD", target_date: 6.months.from_now)

    get goals_url
    assert_response :success

    assert_select "p", text: "Saved this month"
    assert_select "[data-testid=goals-list]"
    # Badge carries a tooltip explaining the on-track basis.
    assert_select "span[data-controller=tooltip] span[role=tooltip]"
  end
end
