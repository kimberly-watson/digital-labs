"""
Changes IQ Server's admin password from the shipped default (admin123) to
a new value via browser automation. IQ Server has no documented REST API
for a user to change their own password (unlike Nexus, which does have
/service/rest/v1/security/users/admin/change-password), so this drives
the actual UI. Selectors below were captured live against a running IQ
Server 1.203.3 instance on 2026-09-04.
"""
import sys
from playwright.sync_api import sync_playwright

NEW_PASSWORD = sys.argv[1] if len(sys.argv) > 1 else "SonatypeLab2026!"

with sync_playwright() as p:
    browser = p.chromium.launch()
    page = browser.new_page()
    page.goto("http://localhost:8070/", timeout=60000)
    page.wait_for_timeout(2000)

    page.fill("#iq-login-modal-username-input", "admin")
    page.fill("#iq-login-modal-password-input", "admin123")
    page.click("button.nx-form__submit-btn")
    page.wait_for_timeout(3000)

    page.click('button[aria-label="Manage User Account"]')
    page.wait_for_timeout(1000)
    page.click("#change-password")
    page.wait_for_timeout(1000)

    page.fill("#original-password", "admin123")
    page.fill("#new-password", NEW_PASSWORD)
    page.fill("#confirm-password", NEW_PASSWORD)
    page.click("#change-password-modal button.nx-form__submit-btn")
    page.wait_for_timeout(2000)

    # Confirm no validation error is showing
    error = page.query_selector(".nx-form__validation-errors")
    if error and error.is_visible():
        print("FAILED: validation error still showing:", error.inner_text())
        sys.exit(1)

    print("IQ Server password changed successfully")
    browser.close()
