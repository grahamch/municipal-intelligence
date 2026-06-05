export interface BillingLine {
    id: number
    bill_id: number
    description: string
    meter_number ?: string | null
    meter_type ?: string | null
    unit ?: string | null
    multiply_factor : number
    previous_reading ?: number | null
    current_reading ?: number | null
    read_type : "actual" | "estimated" | "final" | null
    consumption ?: number | null
    rate : number
    amount : number
    vat_applicable : boolean
    vat_rate ?: number | null
    time_period ?: string | null
    line_period_start ?: string | null
    line_period_end ?: string | null
    created_at : string
  }

 export interface CheckResult {
    bill_id: number
    billing_line_id: number | null
    check_type: string
    passed: boolean
    severity: "info" | "warning" | "error"
    message: string
    calculated_amount: number | null
    billed_amount: number | null
    amount_in_dispute: number | null
  }