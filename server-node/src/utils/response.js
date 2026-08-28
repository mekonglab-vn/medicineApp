/**
 * Standardized API response helpers.
 */
export function success(res, data, statusCode = 200) {
  return res.status(statusCode).json({
    success: true,
    data,
  });
}

export function created(res, data) {
  return success(res, data, 201);
}

export function paginated(res, { items, total, page, limit }) {
  return res.status(200).json({
    success: true,
    data: items,
    pagination: {
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit),
    },
  });
}
