import type { BillingLine, CheckResult } from "../types"

export function estimatedRead(bill_lines: BillingLine[]): CheckResult[] {
   const checkResults: CheckResult[] = []
    for (let i=0; i<bill_lines.length; i++) {
        if (bill_lines[i].read_type !== null) {
        const checkResult: CheckResult = {
            bill_id: bill_lines[i].bill_id,
            billing_line_id: bill_lines[i].id,
            check_type: "estimated_read",
            passed: bill_lines[i].read_type !== "estimated",
            severity: "warning",
            message: bill_lines[i].read_type === "estimated" ? "Estimated read detected - municipality may owe correction" : "Actual read confirmed",
            calculated_amount: null,
            billed_amount: null,
            amount_in_dispute: null
        }
        checkResults.push(checkResult)
    }
    }
    return checkResults
}


