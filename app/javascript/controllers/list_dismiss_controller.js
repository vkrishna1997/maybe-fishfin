import { Controller } from "@hotwired/stimulus";

// Hides an individual suggestion row (and the whole card once empty) without
// persisting anything server-side. Dismissed suggestions reappear on reload
// until the transaction is categorized.
export default class extends Controller {
  static targets = ["item"];

  dismiss(event) {
    const item = event.target.closest("[data-list-dismiss-target='item']");
    if (item) item.remove();

    if (this.itemTargets.length === 0) {
      this.element.remove();
    }
  }
}
