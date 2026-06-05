import { estimatedRead } from "./estimatedRead"
import { BillingLine } from "../types"

function makeBillingLine( overrides: Partial<BillingLine>): BillingLine {
    return {
        id: 12,
        bill_id: 1234,
        description: "The label as it appears on the bill",
        meter_number: null,
        meter_type : "electricity",
        unit : null,
        multiply_factor : 1,
        previous_reading : 456,
        current_reading : 567,
        read_type : "actual",
        consumption : null,
        rate : 1,
        amount : 1,
        vat_applicable : true,
        vat_rate : 0.15,
        time_period : null,
        line_period_start : null,
        line_period_end : null,
        created_at : "some_date",
        ...overrides
    }
}

describe("Municipal checks", () => {
  test("Check 1: Estimated Read", () => {
    const result = estimatedRead([makeBillingLine({ read_type: "estimated"})])
    expect(result[0].passed).toBe(false)
  })
  test("Check 1: Actual Read", () => {
    const result = estimatedRead([makeBillingLine({read_type: "actual"})])
    expect(result[0].passed).toBe(true)
  })
  test("Check 1: read_type null", () => {
    const result = estimatedRead([makeBillingLine({read_type: null})])
    expect(result).toHaveLength(0)
  })
})

