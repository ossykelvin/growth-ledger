-- Allow admins to delete any invoice
CREATE POLICY "Admins can delete invoices"
ON public.tbl_invoices
FOR DELETE
TO authenticated
USING (public.has_module_access(auth.uid(), 'invoices'::app_module, 'admin'::access_level));

-- Allow admins to delete any transaction
CREATE POLICY "Admins can delete transactions"
ON public.tbl_transactions
FOR DELETE
TO authenticated
USING (public.has_module_access(auth.uid(), 'transactions'::app_module, 'admin'::access_level));
