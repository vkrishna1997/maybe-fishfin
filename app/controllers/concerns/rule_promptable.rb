module RulePromptable
  extend ActiveSupport::Concern

  private
    # Sets the "create a category rule?" CTA flash when a transaction's category
    # actually changed and the user is eligible for a prompt. Works for both
    # turbo_stream responses (rendered via flash_notification_stream_items) and
    # full-page redirects (rendered via render_flash_notifications in the layout).
    def set_category_rule_cta(transaction, changed:)
      return unless changed
      return unless rule_prompts_allowed?
      return unless transaction.category_id.present? && transaction.eligible_for_category_rule?

      flash[:cta] = {
        type: "category_rule",
        category_id: transaction.category_id,
        category_name: transaction.category.name
      }
    end

    def rule_prompts_allowed?
      return false if Current.user.rule_prompts_disabled

      if Current.user.rule_prompt_dismissed_at.present?
        return false if (Time.current - Current.user.rule_prompt_dismissed_at) < 1.day
      end

      true
    end
end
