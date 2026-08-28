from core.classify.post_filter import NerPostFilter


def test_post_filter_rejects_dosage_only_text():
    assert NerPostFilter.is_likely_drug("10ml") is False
    assert NerPostFilter.is_likely_drug("Viên sủi") is False


def test_post_filter_keeps_drug_like_text():
    assert NerPostFilter.is_likely_drug("Ginkgo Biloba Tanakan 40mg") is True
