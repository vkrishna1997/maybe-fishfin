require "test_helper"

class GoalTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
  end

  test "progress percent reflects saved vs target" do
    goal = @family.goals.create!(name: "Vacation", target_amount: 1000, current_amount: 250, currency: "USD")
    assert_equal 25.0, goal.progress_percent
  end

  test "progress percent caps at 100" do
    goal = @family.goals.create!(name: "Fund", target_amount: 1000, current_amount: 1500, currency: "USD")
    assert_equal 100.0, goal.progress_percent
    assert goal.completed?
  end

  test "remaining amount never negative" do
    goal = @family.goals.create!(name: "Fund", target_amount: 1000, current_amount: 1500, currency: "USD")
    assert_equal 0, goal.remaining_amount
  end

  test "requires a positive target amount" do
    goal = @family.goals.new(name: "Bad", target_amount: 0, currency: "USD")
    assert_not goal.valid?
    assert_includes goal.errors[:target_amount], "must be greater than 0"
  end

  test "active and completed scopes" do
    active = @family.goals.create!(name: "A", target_amount: 100, current_amount: 10, currency: "USD")
    done = @family.goals.create!(name: "B", target_amount: 100, current_amount: 100, currency: "USD")

    assert_includes @family.goals.active, active
    assert_includes @family.goals.completed, done
    assert_not_includes @family.goals.active, done
  end
end
