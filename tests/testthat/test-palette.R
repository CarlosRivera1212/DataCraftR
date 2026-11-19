test_that("palette is Tableau 10", {
  p <- dcr_palette(10)
  expect_length(p, 10)
  expect_true(all(grepl("^#[0-9A-F]{6}$", p)))
  expect_equal(dcr_palette(3), c("#4E79A7", "#F28E2B", "#E15759"))
  expect_error(dcr_palette(11))
})
